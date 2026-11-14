// swift-tools-version: 6.2
import Foundation
import PackageDescription

// gglib's Swift framework and the llama.cpp framework it links, both taken
// from one gglib release. `GglibFFI` carries gglib's own code for this
// device; `llama` is llama.cpp's own build at the pin that release names,
// which every `GglibFFI` slice loads from `@rpath/llama.framework`. Both are
// dynamic, so the app embeds and signs both. The vendored Swift in
// `Sources/GGLib` is the same release's: uniffi checks it against the
// framework's API checksums at the first call and traps on a mismatch, on a
// device rather than at build time, so the three move together and
// `scripts/check_gglib_take.sh` holds the Swift to the release.
//
// The three lines `scripts/pin_gglib.sh <version>` rewrites, on their own,
// existing only to be rewritten, as modelpipe-ffi's are: a sed against a line
// that does nothing else cannot catch a neighbour, and the script refuses a
// rewrite that left the file as it was. A checksum of zeros pins nothing: it
// names a release that has not been published.
let gglibVersion = "0.36.0"
let gglibChecksum = "1be36e925ba76e38f19784ba6f4798805431b68923184fd20d3d83d8e2619141"
let llamaChecksum = "1e9c1331fd8a051a811772a5e5e85aebb40b2d770e7df99d17bfa87073f31d7f"

// Local development: `GGLIB_FFI_LOCAL_XCFRAMEWORK=1` swaps both downloads for
// the frameworks in `build/`, which `scripts/pin_gglib.sh --local <gglib
// checkout>` fills from that checkout's own build. An environment switch,
// not a toggle in this file, for modelpipe-ffi's reason: the default is the
// release, so a manifest committed mid-development cannot point at a build
// nobody else has. `build/` and not the checkout itself, because SwiftPM
// takes a binary target's path only relative to the package root.
//
// SwiftPM and Xcode cache what a manifest evaluated to, and the artifacts it
// named, and a cache that missed a flip of the switch builds against the
// other framework without a word. After flipping it, `swift package reset`
// resolves afresh for `swift build`, and Reset Package Caches (or deleting the
// project's DerivedData) does for Xcode.
let gglibRelease = "https://github.com/mmogr/gglib/releases/download/v\(gglibVersion)"
let gglibFrameworks: [Target] =
    ProcessInfo.processInfo.environment["GGLIB_FFI_LOCAL_XCFRAMEWORK"] == nil
    ? [
        .binaryTarget(
            name: "GglibFFI", url: "\(gglibRelease)/GglibFFI-\(gglibVersion).xcframework.zip", checksum: gglibChecksum),
        .binaryTarget(
            name: "llama", url: "\(gglibRelease)/llama-\(gglibVersion).xcframework.zip", checksum: llamaChecksum),
    ]
    : [
        .binaryTarget(name: "GglibFFI", path: "build/GglibFFI.xcframework"),
        .binaryTarget(name: "llama", path: "build/llama.xcframework"),
    ]

let package = Package(
    name: "ggchat",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GGChatCore", targets: ["GGChatCore"]),
        .library(name: "GGChatPipe", targets: ["GGChatPipe"]),
        .library(name: "GGChatLocal", targets: ["GGChatLocal"]),
        .library(name: "GGChatUI", targets: ["GGChatUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.5.0"),
        // Draws the math in a reply. A revision rather than a version: the
        // last release, 1.7.3, predates `\operatorname`, `\tfrac` and
        // `\boldsymbol`, which models write and main has. Move to a version
        // once one is tagged past this commit.
        .package(
            url: "https://github.com/mgriebling/SwiftMath.git", revision: "0b0222e102ba415b352cd29f334075622bd4e6aa"),
        // Pinned to a version, never a branch. The binding and the
        // xcframework are two halves of one artifact checked against each
        // other by a uniffi checksum, and a mismatch is a `fatalError` at the
        // first dial on a device rather than an error at build time.
        //
        // Up to the next minor, not the next major: every ffi feature is a
        // minor release, and a minor can add a protocol requirement, as 0.2.0
        // did to `MpPipeProtocol`, or a case to an error, as 0.4.0 did to
        // `MpPairError`. Taking one is then a deliberate pull request rather
        // than a dependency bump that arrives red.
        .package(url: "https://github.com/mmogr/modelpipe-ffi.git", .upToNextMinor(from: "0.4.0")),
    ],
    targets: gglibFrameworks + [
        .target(
            name: "GGChatCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        // The one target that links modelpipe, and the only place the
        // boundary check permits `import Modelpipe`.
        //
        // Not `GGChatCore`: that target is kept free of the *binding* so it
        // builds and tests from a command line, and the binding links Apple
        // frameworks. It is not free of Apple frameworks as such — `Ticket`
        // takes CryptoKit. Not `GGChatUI` either: its `.defaultIsolation(MainActor)`
        // fights `PipeConnector: Sendable`, which the connector must be.
        .target(
            name: "GGChatPipe",
            dependencies: [
                "GGChatCore",
                .product(name: "Modelpipe", package: "modelpipe-ffi"),
            ]
        ),
        // gglib's generated Swift, vendored from the release and never
        // edited: the four files of its swift zip. The framework carries its
        // own header and `Modules/module.modulemap`, so the binding's
        // `import GglibFFI` needs no C target, and the zip's copies are kept
        // only so the directory is the zip, byte for byte.
        //
        // `llama` is a dependency though nothing imports it, so that Xcode
        // embeds and signs the framework `GglibFFI` loads, beside it.
        .target(
            name: "GGLib",
            dependencies: ["GglibFFI", "llama"],
            exclude: ["GglibFFI.h", "module.modulemap", "binding.json"]
        ),
        // The one target that imports the binding, and the only place the
        // boundary check permits `import GGLib`: it says gglib's records in
        // GGChatCore's own types, as GGChatPipe says modelpipe's, so nothing
        // above it names a binding type.
        .target(
            name: "GGChatLocal",
            dependencies: ["GGChatCore", "GGLib"]
        ),
        .target(
            name: "GGChatUI",
            dependencies: ["GGChatCore", "GGChatPipe", "GGChatLocal", "SwiftMath"],
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
        // GGChatUI too, to walk the app model on gglib's engine type, faked
        // at the binding: only this target may import the binding.
        .testTarget(
            name: "GGChatLocalTests",
            dependencies: ["GGChatLocal", "GGChatCore", "GGChatUI"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "GGChatUITests",
            dependencies: ["GGChatUI", "GGChatCore", "GGChatLocal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
