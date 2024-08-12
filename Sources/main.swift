import Foundation
import CX11
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

let defaultXErrorHandler = XSetErrorHandler { _, _ in fatalError("swm: another window manager is already running!") }!

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
