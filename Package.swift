// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XprinterSetup",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "XprinterKit", resources: [.process("Resources")]),
        .executableTarget(
            name: "XprinterSetup",
            dependencies: ["XprinterKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "XprinterKitTests", dependencies: ["XprinterKit"]),
    ]
)
