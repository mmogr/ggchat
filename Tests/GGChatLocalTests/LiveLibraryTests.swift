import Foundation
import GGChatCore
import XCTest

@testable import GGChatLocal

/// gglib's library against Hugging Face itself: a search, and a
/// repository's quantizations judged against a phone's reading. Runs only
/// with `GGCHAT_LIVE_HF=1`, which `make test-live-library` sets, and skips
/// otherwise, so neither `make ci` nor CI ever reaches the network here.
final class LiveLibraryTests: XCTestCase {
    /// A small public repository of GGUF quantizations.
    private static let repo = "Qwen/Qwen3-0.6B-GGUF"

    private let root = FileManager.default.temporaryDirectory
        .appending(path: "ggchat-live-library-\(UUID().uuidString)").resolvingSymlinksInPath()
    private var dataRoot: GglibDataRoot?

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GGCHAT_LIVE_HF"] == "1",
            "set GGCHAT_LIVE_HF=1 to search Hugging Face (make test-live-library)")
        dataRoot = GglibDataRoot(under: root)
    }

    override func tearDownWithError() throws {
        dataRoot?.restore()
        try? FileManager.default.removeItem(at: root)
    }

    private func library() -> GglibLibrary {
        GglibLibrary(
            folders: LibraryFolders(
                data: root.appending(path: LibraryFolders.dataDirectoryName),
                models: root.appending(path: "ggchat-models")))
    }

    func testASearchOfHuggingFaceFindsChatModels() async throws {
        let page = try await library().search(query: "Qwen3 0.6B", cursor: nil)

        XCTAssertFalse(page.hits.isEmpty, "Hugging Face found nothing for Qwen3 0.6B")
        XCTAssertTrue(page.hits.allSatisfy { $0.repo.contains("/") }, "\(page.hits.map(\.repo))")
    }

    /// Every quantization carries its size and a verdict made against the
    /// reading: one gglib judged, or one it says why it could not.
    func testARepositorysQuantizationsAreSizedAndJudged() async throws {
        let reading = DeviceReading(physicalBytes: 8 << 30, availableBytes: 6 << 30, isSimulator: false)
        let offers = try await library().quantizations(repo: Self.repo, reading: reading)

        XCTAssertFalse(offers.isEmpty, "\(Self.repo) offered no quantization")
        XCTAssertTrue(offers.allSatisfy { $0.totalBytes > 0 }, "\(offers)")
        XCTAssertTrue(
            offers.contains {
                if case .fits = $0.verdict { return true }
                return false
            }, "no quantization of a 0.6B model fits 6 GB: \(offers.map(\.verdict))")
    }
}
