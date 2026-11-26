// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hide-a-hole",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "hide-a-hole"),
        .testTarget(name: "HideAHoleTests", dependencies: ["hide-a-hole"])
    ]
)
