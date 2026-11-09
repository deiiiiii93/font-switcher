// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FontSwitcher",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FontSwitcher", targets: ["FontSwitcher"]),
        .library(name: "FontSwitcherCore", targets: ["FontSwitcherCore"]),
    ],
    targets: [
        .target(name: "FontSwitcherCore"),
        .executableTarget(name: "FontSwitcher", dependencies: ["FontSwitcherCore"]),
        .testTarget(name: "FontSwitcherCoreTests", dependencies: ["FontSwitcherCore"]),
    ]
)
