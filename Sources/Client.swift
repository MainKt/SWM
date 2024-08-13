import CX11

struct Client {
    let window: Window
    var tags: UInt
    var hidden, fullScreen: Bool
    var geometry: (x: Int32, y: Int32, width: Int32, height: Int32)
}