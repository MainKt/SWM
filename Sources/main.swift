import CX11
import Foundation
import Logging

let logger = Logger(label: "SWM")

guard let display = XOpenDisplay(nil) else {
    fatalError("Failed to open display")
}

logger.debug("Successfully opened display")

let defaultConfig = Config(
    border: (
        borderWidth: 2,
        color: (focused: 0xFFFFFF, unfocused: 0x000000)
    ),
    gap: (inner: 4, outer: 4),
    mouseMask: UInt(Mod4Mask)
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
        fatalError("swm: another window manager is already running!")
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
logger.debug("Successfully assigned atoms")