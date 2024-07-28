import Foundation
import CX11

var stderr = FileHandle.standardError

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    let data = Data(string.utf8)
    self.write(data)
  }
}

@main
class SWM {
    private var display: OpaquePointer
    private var root: Window
    private let screen: (number: Int32, width: UInt32, height: UInt32)
    private let border  = (width: UInt32(2), focusColor: UInt(0xffd787), normalColor: UInt(0x333333));
    private var running = true
    private var focusedWindow: Window?

    init() {
        guard let display = XOpenDisplay(nil) else {
            fatalError("Failed to open display")
        }

        self.display = display
        self.root = XDefaultRootWindow(display)
        let screen = XDefaultScreen(display)
        self.screen = (number: screen, width: UInt32(XDisplayWidth(display, screen)), height: UInt32(XDisplayHeight(display, screen)))
    }

    deinit {
        XCloseDisplay(display)
    }

    func run() {
        XSelectInput(display, root, SubstructureRedirectMask | SubstructureNotifyMask | KeyPressMask)

        grabKeys()

        var event = XEvent()
        while running && XNextEvent(display, &event) == 0 {
            switch event.type {
            case MapRequest:
                handleMapRequest(event.xmaprequest);
            case ConfigureRequest:
                handleConfigureRequest(event.xconfigurerequest)
            case KeyPress:
                handleKeyPress(event.xkey)
            case ButtonPress:
                handleButtonPress(event.xbutton)
            default:
                break
            }
        }
    }

    private func grabKeys() {
        let modifiers = UInt32(Mod4Mask)

        XGrabKey(display, Int32(XKeysymToKeycode(display, KeySym(XK_Q))), modifiers, root, True, GrabModeAsync, GrabModeAsync)
        XGrabKey(display, Int32(XKeysymToKeycode(display, KeySym(XK_F))), modifiers, root, True, GrabModeAsync, GrabModeAsync)
        XGrabKey(display, Int32(XKeysymToKeycode(display, KeySym(XK_H))), modifiers, root, True, GrabModeAsync, GrabModeAsync)
        XGrabKey(display, Int32(XKeysymToKeycode(display, KeySym(XK_L))), modifiers, root, True, GrabModeAsync, GrabModeAsync)
        XGrabKey(display, Int32(XKeysymToKeycode(display, KeySym(XK_Return))), modifiers, root, True, GrabModeAsync, GrabModeAsync)
        XGrabKey(display, Int32(XKeysymToKeycode(display, KeySym(XK_P))), modifiers, root, True, GrabModeAsync, GrabModeAsync)

        XGrabButton(display, 1, UInt32(Mod4Mask), root, 0, UInt32(ButtonPressMask | ButtonReleaseMask | PointerMotionMask), GrabModeAsync, GrabModeAsync, 0, 0);
        XGrabButton(display, 3, UInt32(Mod4Mask), root, 0, UInt32(ButtonPressMask | ButtonReleaseMask | PointerMotionMask), GrabModeAsync, GrabModeAsync, 0, 0);
    }

    private func handleMapRequest(_ event: XMapRequestEvent) {
        let window = event.window
        XSelectInput(display, window, StructureNotifyMask | EnterWindowMask)
        XMapWindow(display, window)
        XSetWindowBorderWidth(display, window, border.width);
        focusWindow(window)
    }

    private func focusWindow(_ window: Window) {
        if let focusedWindow = focusedWindow {
            XSetWindowBorder(display, focusedWindow, border.normalColor)
        }
        XSetInputFocus(display, window, RevertToParent, UInt(CurrentTime))
        XRaiseWindow(display, window)
        XSetWindowBorder(display, window, border.focusColor)
        focusedWindow = window
    }

    private func handleConfigureRequest(_ event: XConfigureRequestEvent) {
        var changes = XWindowChanges()
        changes.x = event.x
        changes.y = event.y
        changes.width = event.width
        changes.height = event.height
        changes.border_width = event.border_width
        changes.sibling = event.above
        changes.stack_mode = event.detail
        XConfigureWindow(display, event.window, UInt32(event.value_mask), &changes)
    }

    private func handleKeyPress(_ event: XKeyEvent) {
        let keycode = KeyCode(event.keycode)
        let modifiers = event.state

        if modifiers & UInt32(Mod4Mask) != 0 {
            switch keycode {
            case XKeysymToKeycode(display, KeySym(XK_Q)):
                running = false
            case XKeysymToKeycode(display, KeySym(XK_F)):
                toggleFullScreen(event.window)
            case XKeysymToKeycode(display, KeySym(XK_H)):
                snapWindow(event.window, .left)
            case XKeysymToKeycode(display, KeySym(XK_L)):
                snapWindow(event.window, .right)
            case XKeysymToKeycode(display, KeySym(XK_Return)):
                launchProgram("alacritty")
            case XKeysymToKeycode(display, KeySym(XK_P)):
                launchProgram("dmenu_run")
            default:
                break
            }
        }
    }

    private func handleButtonPress(_ event: XButtonPressedEvent) {
        focusWindow(event.window)
    }
    
    private func toggleFullScreen(_ window: Window) {
        var attributes = XWindowAttributes()
        XGetWindowAttributes(display, window, &attributes)

        XMoveResizeWindow(display, window, Int32(border.width), Int32(border.width), screen.width - 3 * border.width, screen.height - 3 * border.width);
    }

    private enum SnapPosition {
        case left, right
    }

    private func snapWindow(_ window: Window, _ position: SnapPosition) {
        var attributes = XWindowAttributes()
        XGetWindowAttributes(display, window, &attributes)

        var changes = XWindowChanges()
        changes.width = Int32(screen.width / 2)
        changes.height = Int32(screen.height)
        changes.y = 0

        switch position {
        case .left:
            changes.x = 0
        default:
            changes.x = Int32(screen.width / 2)
        }

        XConfigureWindow(display, window, UInt32(CWX | CWY | CWWidth | CWHeight), &changes)
    }

    private func launchProgram(_ program: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [program]
        do {
            try task.run()
        } catch {
            print("Failed to launch \(program)", to: &stderr)
        }
    }

    public static func main() {
        SWM().run()
    }
}