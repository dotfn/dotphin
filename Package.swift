// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Dotphin",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(
            name: "Dotphin",
            path: "Sources/Dotphin",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.icon"),
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(name: "DotphinTests", dependencies: ["Dotphin"], path: "Tests/DotphinTests"),
    ]
)
