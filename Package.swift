// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SWM",
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "swm",
            dependencies: [
                "CX11",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources"
        ),
        .systemLibrary(
            name: "CX11",
            pkgConfig: "x11"
        ),
    ]
)
