// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FocusSession",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FocusSessionCore",
            targets: ["FocusSessionCore"]
        ),
        .executable(
            name: "FocusSessionApp",
            targets: ["FocusSessionApp"]
        ),
        .executable(
            name: "FocusSessionNativeHost",
            targets: ["FocusSessionNativeHost"]
        )
    ],
    targets: [
        .target(
            name: "FocusSessionCore"
        ),
        .executableTarget(
            name: "FocusSessionApp",
            dependencies: ["FocusSessionCore"]
        ),
        .executableTarget(
            name: "FocusSessionNativeHost",
            dependencies: ["FocusSessionCore"]
        ),
        .testTarget(
            name: "FocusSessionCoreTests",
            dependencies: ["FocusSessionCore"]
        )
    ]
)
