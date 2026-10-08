// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TokenBar", resources: [.process("Resources")]),
        .testTarget(name: "TokenBarTests", dependencies: ["TokenBar"]),
    ]
)
