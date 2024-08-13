import CX11
import Foundation
import Logging

var logger = Logger(label: "SWM")
#if DEBUG
    logger.logLevel = .debug
#endif

guard let display = XOpenDisplay(nil) else {
    fatalError("Failed to open display")
}

logger.debug("Successfully opened display")

let defaultConfig = Config(
    border: (
        width: 2,
        color: (focused: 0xFFFFFF, unfocused: 0x000000)
    ),
    gap: (inner: 4, outer: 4),
    mouse: (mouseMask: UInt32(Mod4Mask), moveButton: 1, resizeButton: 3),
    totalWorkspaces: 10
)

let root = XDefaultRootWindow(display)
let screen = {
    (number: $0, width: XDisplayWidth(display, $0), height: XDisplayWidth(display, $0))
}(XDefaultScreen(display))

let cursor = (
    move: XCreateFontCursor(display, UInt32(XC_crosshair)),
    normal: XCreateFontCursor(display, UInt32(XC_left_ptr))
)
XDefineCursor(display, root, cursor.normal)

let defaultXErrorHandler = XSetErrorHandler { _, _ in
    #if DEBUG
        logger.warning("ignoring another wm check")
        return 0
    #else
        fatalError("Another window manager is already running!")
    #endif
}!

XSelectInput(
    display,
    root,
    StructureNotifyMask
        | SubstructureRedirectMask
        | SubstructureNotifyMask
        | ButtonPressMask
        | Int(Button1Mask)
)
XSync(display, False)

XSetErrorHandler { display, errorEventPointer in
    if let errorEvent = errorEventPointer?.pointee {
        switch (Int32(errorEvent.error_code), Int32(errorEvent.request_code)) {
        case (BadWindow, _):
            return 0
        case (BadMatch, X_SetInputFocus),
         (BadDrawable, X_PolyText8),
         (BadDrawable, X_PolyFillRectangle),
         (BadDrawable, X_PolySegment),
         (BadMatch, X_ConfigureWindow),
         (BadAccess, X_GrabButton),
         (BadAccess, X_GrabKey),
         (BadDrawable, X_CopyArea):
            return 0
        default:
            logger.error("fatal error: request code=\(errorEvent.request_code), error code = \(errorEvent.error_code)")
        }
    }
    return defaultXErrorHandler(display, errorEventPointer)
}

XSync(display, False)

let noFocusWindow = XCreateSimpleWindow(display, root, -10, -10, 1, 1, 0, 0, 0)
do {
    var attributes = XSetWindowAttributes()
    attributes.override_redirect = True
    XChangeWindowAttributes(
        display,
        noFocusWindow,
        UInt(CWOverrideRedirect),
        &attributes
    )
}

XMapWindow(display, noFocusWindow)
XSetInputFocus(display, noFocusWindow, Int32(RevertToPointerRoot), Time(CurrentTime))

let netAtom = Dictionary(uniqueKeysWithValues: NetAtom.allCases.map { ($0, XInternAtom(display, $0.rawValue, False)) })
let wmAtom = Dictionary(uniqueKeysWithValues: WMAtom.allCases.map { ($0, XInternAtom(display, $0.rawValue, False)) })
let utf8StringAtom = XInternAtom(display, "UTF8_STRING", False)
logger.debug("Successfully assigned atoms")

var checkWindow = XCreateSimpleWindow(display, root, 0, 0, 1, 1, 0, 0, 0)
XChangeProperty(display, checkWindow, netAtom[.wmCheck]!, XA_WINDOW, 32, PropModeReplace, &checkWindow, 1)
XChangeProperty(display, checkWindow, netAtom[.wmName]!, utf8StringAtom, 8, PropModeReplace, "swm", 5)

XChangeProperty(display, root, netAtom[.wmCheck]!, XA_WINDOW, 32, PropModeReplace, &checkWindow, 1)

var netAtoms = Array(netAtom.values)
XChangeProperty(display, root, netAtom[.supported]!, XA_ATOM, 32, PropModeReplace, &netAtoms, Int32(netAtoms.count))
logger.debug("Successfully set initial properties")

XChangeProperty(display, root, netAtom[.numberOfDesktops]!, XA_CARDINAL, 32, PropModeReplace, [UInt8(defaultConfig.totalWorkspaces)], 1)
let currentWorkspace = 0
XChangeProperty(display, root, netAtom[.currentDesktop]!, XA_CARDINAL, 32, PropModeReplace, [UInt8(currentWorkspace)], 1)

logger.debug("Setting up monitors")
typealias Monitor = (x: Int16, y: Int16, width: Int16, height: Int16, screen: Int32)
var monitors: [Monitor] = []
if XineramaIsActive(display) == True {
    var totalScreens: Int32 = 0
    if let monitorInfo = XineramaQueryScreens(display, &totalScreens) {
        logger.debug("Found \(totalScreens) screens active")

        let monitorArray = Array(UnsafeBufferPointer(start: monitorInfo, count: Int(totalScreens)))
            .map {
                let monitor = Monitor(x: $0.x_org, y: $0.y_org, width: $0.width, height: $0.height, screen: $0.screen_number)
                logger.debug("Screen \(monitor.screen) with dimensions: x=\(monitor.x) y=\(monitor.y) w=\(monitor.width) h=\(monitor.height)")
                return monitor
            }

        monitors.append(contentsOf: monitorArray)
        XChangeProperty(display, root, netAtom[.desktopViewport]!, XA_CARDINAL, 32, PropModeReplace, [0, 0], 2)
    } else {
        logger.debug("Xinerama could not query screens")
    }
} else {
    logger.debug("Xinerama not active, cannot read monitors")
}

logger.debug("Successfully setup monitors")

XWarpPointer(
    display,
    Window(None),
    root,
    0, 0, 0, 0,
    Int32(monitors.first!.x + monitors.first!.width / 2),
    Int32(monitors.first!.y + monitors.first!.height / 2)
)

do {
    var workspaces = (0 ..< defaultConfig.totalWorkspaces)
        .map { strdup(String($0)) }
    var textProp = XTextProperty()
    Xutf8TextListToTextProperty(display, &workspaces, Int32(defaultConfig.totalWorkspaces), XUTF8StringStyle, &textProp)
    XSetTextProperty(display, root, &textProp, netAtom[.desktopNames]!)
    workspaces.forEach { free($0) }
}

let eventHandler = [
    MapRequest: { (e: XEvent) in
        let mapRequest = e.xmaprequest
        var attributes = XWindowAttributes()
        guard XGetWindowAttributes(display, mapRequest.window, &attributes) == True else { return }
        guard attributes.override_redirect == False else { return }

        var propReturn: UnsafeMutablePointer<UInt8>?
        var dummyAtom = Atom()
        var dummyInt = Int32()
        var dummyUInt1 = UInt(), dummyUInt2 = UInt()
        if XGetWindowProperty(display, mapRequest.window, netAtom[.wmWindowType]!, 0, MemoryLayout<Atom>.size, False, XA_ATOM, &dummyAtom, &dummyInt, &dummyUInt1, &dummyUInt2, &propReturn) == Success {
            if let propReturn {
                let prop = Atom(propReturn.pointee)
                let atoms = [
                    netAtom[.wmWindowTypeDock]!,
                    netAtom[.wmWindowTypeToolbar]!,
                    netAtom[.wmWindowTypeUtility]!,
                    netAtom[.wmWindowTypeDialog]!,
                    netAtom[.wmWindowTypeMenu]!,
                ]
                if atoms.contains(prop) {
                    logger.debug("Window is of type dock, toolbar, utility, menu or splash: not managing")
                    logger.debug("Mapping new window, not managed")
                    XMapWindow(display, mapRequest.window)
                    return
                }
            }
        }

        var classHint = XClassHint()
        if XGetClassHint(display, mapRequest.window, &classHint) > Success {
            if let resClass = classHint.res_class {
                logger.debug("Client has class \(resClass)")
                XFree(classHint.res_class)
            }
            if let resName = classHint.res_name {
                logger.debug("Client has name \(resName)")
                XFree(classHint.res_name)
            }
        } else {
            logger.debug("Could not retrieve client class name")
        }

        let client = Client(
            window: mapRequest.window,
            tags: 1 << 0,
            hidden: false,
            fullScreen: false,
            geometry: (x: attributes.x, y: attributes.y, width: attributes.width, height: attributes.height)
        )

        XSetWindowBorder(display, client.window, defaultConfig.border.color.focused)
        XSetWindowBorderWidth(display, client.window, defaultConfig.border.width)

        XChangeProperty(display, client.window, netAtom[.wmDesktop]!, XA_CARDINAL, 32, PropModeReplace, [0], 1)

        XMapWindow(display, client.window)

        XSelectInput(display, client.window, EnterWindowMask | FocusChangeMask | PropertyChangeMask | StructureNotifyMask)

        XGrabButton(display, defaultConfig.mouse.moveButton, defaultConfig.mouse.mouseMask, client.window, True, UInt32(ButtonPressMask | ButtonReleaseMask | PointerMotionMask), GrabModeAsync, GrabModeAsync, Window(None), Cursor(None))
        XGrabButton(display, defaultConfig.mouse.resizeButton, defaultConfig.mouse.mouseMask, client.window, True, UInt32(ButtonPressMask | ButtonReleaseMask | PointerMotionMask), GrabModeAsync, GrabModeAsync, Window(None), Cursor(None))
    },
    UnmapNotify: { (e: XEvent) in },
    ConfigureNotify: { (e: XEvent) in },
    ConfigureRequest: { (e: XEvent) in
        let configureRequest = e.xconfigurerequest
        var windowChanges = XWindowChanges(
            x: configureRequest.x,
            y: configureRequest.y,
            width: configureRequest.width,
            height: configureRequest.height,
            border_width: configureRequest.border_width,
            sibling: configureRequest.above,
            stack_mode: configureRequest.detail
        )
        XConfigureWindow(display, configureRequest.window, UInt32(configureRequest.value_mask), &windowChanges)
    },
    ClientMessage: { (e: XEvent) in },
    ButtonPress: { (e: XEvent) in },
    PropertyNotify: { (e: XEvent) in },
    Expose: { (e: XEvent) in },
    FocusIn: { (e: XEvent) in },
    EnterNotify: { (e: XEvent) in },
]

var running = true
var event = XEvent()
while running {
    XNextEvent(display, &event)
    logger.debug("Recieved new \(event.type) event")
    eventHandler[event.type]?(event)
}
