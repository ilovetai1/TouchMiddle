// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchMiddle",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TouchMiddle", targets: ["TouchMiddle"])],
    targets: [
        .target(name: "TouchMiddleCore"),
        .target(name: "CTouchBridge", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .executableTarget(name: "TouchMiddle", dependencies: ["TouchMiddleCore", "CTouchBridge"]),
        .testTarget(name: "TouchMiddleCoreTests", dependencies: ["TouchMiddleCore"]),
        .testTarget(name: "TouchMiddleAppTests", dependencies: ["TouchMiddle"])
    ]
)
