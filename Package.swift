// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DolphinForMacOS",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(name: "DolphinForMacOS", path: "Sources/DolphinForMacOS"),
        .testTarget(name: "DolphinForMacOSTests", dependencies: ["DolphinForMacOS"], path: "Tests/DolphinForMacOSTests"),
    ]
)
