// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShortcutField",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ShortcutField", targets: ["ShortcutField"])
    ],
    targets: [
        .target(name: "ShortcutField"),
        .testTarget(name: "ShortcutFieldTests", dependencies: ["ShortcutField"])
    ]
)
