// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Contexture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ContextureKit", targets: ["ContextureKit"]),
        .library(name: "SelectionBridge", targets: ["SelectionBridge"]),
        .library(name: "BridgeClient", targets: ["BridgeClient"]),
        .executable(name: "ContextureApp", targets: ["ContextureApp"])
    ],
    targets: [
        .target(name: "ContextureKit"),
        .target(
            name: "SelectionBridge",
            dependencies: ["ContextureKit"]
        ),
        .target(
            name: "BridgeClient",
            dependencies: ["ContextureKit"]
        ),
        .executableTarget(
            name: "ContextureApp",
            dependencies: ["ContextureKit", "SelectionBridge"],
            resources: [
                .copy("Resources/editor")
            ]
        ),
        .testTarget(
            name: "ContextureKitTests",
            dependencies: ["ContextureKit"]
        ),
        .testTarget(
            name: "SelectionBridgeTests",
            dependencies: ["SelectionBridge", "ContextureKit"]
        )
    ]
)
