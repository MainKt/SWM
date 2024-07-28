// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SWM",
    targets: [
        .executableTarget(
            name: "swm",
            dependencies: ["CX11"],
            path: "Sources"),
        .systemLibrary(
            name: "CX11",
            pkgConfig: "x11"),
    ]
)
