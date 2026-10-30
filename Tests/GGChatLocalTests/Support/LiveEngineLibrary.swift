import Foundation
import GGChatCore
import XCTest

@testable import GGChatLocal

/// A gglib library holding tinygemma3, made in a scratch folder for a test
/// that serves gglib's engine on the Mac's slice, and the engine served from
/// that library's own handle, as the app serves it.
///
/// Runs only with `GGLIB_ENGINE_MODELS_DIR` naming the folder that holds
/// `tinygemma3-Q8_0.gguf`, gglib's recorder's tiny model, and skips
/// otherwise, so `swift test` and CI stay hermetic. The binding has no call
/// that adds a file, so the model is added by gglib's own
/// `gglib-ffi-add-model`, which `GGLIB_FFI_ADD_MODEL` names: built in a gglib
/// checkout with `cargo build -p gglib-ffi --features smoke --bin
/// gglib-ffi-add-model`, as gglib's `swift-smoke.sh` builds it.
struct LiveEngineLibrary {
    static let modelFile = "tinygemma3-Q8_0.gguf"

    /// The scratch folder, which ``remove()`` takes away.
    let root: URL
    /// gglib's own data root, pointed into ``root`` until ``remove()``.
    let dataRoot: GglibDataRoot
    /// The name the tool says the model is served under.
    let name: String
    let engine: GglibEngine

    /// A reading of a phone with room for tinygemma3 many times over.
    static let reading = DeviceReading(physicalBytes: 8 << 30, availableBytes: 6 << 30, isSimulator: false)

    static func make() throws -> LiveEngineLibrary {
        let environment = ProcessInfo.processInfo.environment
        guard let models = environment["GGLIB_ENGINE_MODELS_DIR"], !models.isEmpty else {
            throw XCTSkip("GGLIB_ENGINE_MODELS_DIR is not set; `make test-live-engine` says what it needs")
        }
        guard let tool = environment["GGLIB_FFI_ADD_MODEL"], !tool.isEmpty else {
            throw XCTSkip("GGLIB_FFI_ADD_MODEL does not name gglib's gglib-ffi-add-model")
        }
        let gguf = URL(filePath: models).appending(path: modelFile)
        guard FileManager.default.fileExists(atPath: gguf.path(percentEncoded: false)) else {
            throw XCTSkip("\(gguf.path(percentEncoded: false)) is not there")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "ggchat-live-engine-\(UUID().uuidString)")
        let folders = LibraryFolders(
            data: root.appending(path: LibraryFolders.dataDirectoryName, directoryHint: .isDirectory),
            models: root.appending(path: "ggchat-models", directoryHint: .isDirectory))
        try folders.prepare()
        let dataRoot = GglibDataRoot(under: root)
        let name: String
        do {
            name = try add(gguf, data: folders.data, models: folders.models, with: URL(filePath: tool))
        } catch {
            dataRoot.restore()
            throw error
        }
        let engine = GglibEngine(library: GglibLibrary(folders: folders))
        return LiveEngineLibrary(root: root, dataRoot: dataRoot, name: name, engine: engine)
    }

    /// The tool was there and did not add the model: a failure, not a skip.
    struct ToolFailed: Error, CustomStringConvertible {
        let status: Int32
        var description: String { "gglib-ffi-add-model exited \(status)" }
    }

    func remove() {
        dataRoot.restore()
        try? FileManager.default.removeItem(at: root)
    }

    /// Runs the tool, which adds `gguf` where it lies and prints its name.
    private static func add(_ gguf: URL, data: URL, models: URL, with tool: URL) throws -> String {
        let process = Process()
        process.executableURL = tool
        process.arguments = [data, models, gguf].map { $0.path(percentEncoded: false) }
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ToolFailed(status: process.terminationStatus) }
        return String(decoding: printed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
