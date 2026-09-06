// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ggchat",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GGChatCore", targets: ["GGChatCore"]),
        .library(name: "GGChatUI", targets: ["GGChatUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "GGChatCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .target(
            name: "GGChatUI",
            dependencies: ["GGChatCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "GGChatCoreTests",
            dependencies: ["GGChatCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "GGChatUITests",
            dependencies: ["GGChatUI", "GGChatCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
