// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ggchat",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GGChatCore", targets: ["GGChatCore"]),
        .library(name: "GGChatPipe", targets: ["GGChatPipe"]),
        .library(name: "GGChatUI", targets: ["GGChatUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
        // Pinned to a version, never a branch. The binding and the
        // xcframework are two halves of one artifact checked against each
        // other by a uniffi checksum, and a mismatch is a `fatalError` at the
        // first dial on a device rather than an error at build time.
        .package(url: "https://github.com/mmogr/modelpipe-ffi.git", from: "0.1.3"),
    ],
    targets: [
        .target(
            name: "GGChatCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        // The one target that links modelpipe, and the only place the
        // boundary check permits `import Modelpipe`.
        //
        // Not `GGChatCore`: that target is kept free of anything Apple-only so
        // it builds and tests from a command line, and the binding links Apple
        // frameworks. Not `GGChatUI` either: its `.defaultIsolation(MainActor)`
        // fights `PipeConnector: Sendable`, which the connector must be.
        .target(
            name: "GGChatPipe",
            dependencies: [
                "GGChatCore",
                .product(name: "Modelpipe", package: "modelpipe-ffi"),
            ]
        ),
        .target(
            name: "GGChatUI",
            dependencies: ["GGChatCore", "GGChatPipe"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "GGChatCoreTests",
            dependencies: ["GGChatCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "GGChatPipeTests",
            dependencies: ["GGChatPipe", "GGChatCore"]
        ),
        .testTarget(
            name: "GGChatUITests",
            dependencies: ["GGChatUI", "GGChatCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
