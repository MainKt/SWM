struct Config {
    let border: (width: UInt32, color: (focused: UInt, unfocused: UInt))
    let gap: (inner: UInt, outer: UInt)
    let mouse: (mouseMask: UInt32, moveButton: UInt32, resizeButton: UInt32)
    let totalWorkspaces: UInt
}
