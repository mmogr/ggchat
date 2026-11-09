import Foundation
import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// What gglib says of an installed model's quantization and repository:
/// the app shows a model on this device by its name and its quantization,
/// and the browser marks a repository's variant as on this iPhone from what
/// is installed, which a relaunch keeps, and unmarks only the one removed.
@MainActor
final class OnThisIPhoneMarksTests: XCTestCase {
    private let phoneRepo = MockLibrary.phoneRepo
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)

    /// "name · QUANT" where gglib labels the model, the name alone where it
    /// does not.
    func testAModelOnThisIPhoneIsShownWithItsQuantization() {
        let labelled = InstalledModel(
            id: 3, name: "Qwen3 4B", quantization: "UD-Q4_K_XL", repo: "unsloth/Qwen3-4B-GGUF", bytes: 1,
            trainedCtx: nil, capabilities: [], verdict: .fits(ctx: 4_096))
        XCTAssertEqual(labelled.shownName, "Qwen3 4B · UD-Q4_K_XL")
        var bare = labelled
        bare.quantization = nil
        XCTAssertEqual(bare.shownName, "Qwen3 4B")
        XCTAssertEqual(OnThisIPhoneSection.removalQuestion(for: labelled), "Remove Qwen3 4B · UD-Q4_K_XL?")
    }

    /// Two variants of the phone's repository installed before this launch,
    /// with no download followed in it, are each marked as on this iPhone,
    /// and the others are not. Removing one unmarks it and forgets its
    /// finished download alone; the other stays marked, its download too.
    func testTheBrowserMarksWhatIsInstalledAndARemovalUnmarksItAlone() async throws {
        let catalogue = MockLibrary.Catalogue(behaviour: .noModels)
        let library = MockLibrary(behaviour: .noModels, catalogue: catalogue)
        let offers = try await library.quantizations(repo: phoneRepo, reading: reading)
        let small = try XCTUnwrap(offers.first { $0.label == "Q4_K_M" })
        let large = try XCTUnwrap(offers.first { $0.label == "Q8_0" })
        for offer in [small, large] {
            catalogue.install(offer, of: phoneRepo, as: MockLibrary.installedName(repo: phoneRepo))
        }
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: MockEngine(behaviour: .noModels, registry: registry, catalogue: catalogue), library: library,
            diagnostics: Diagnostics(
                defaults: UserDefaults(suiteName: "OnThisIPhoneMarksTests.\(UUID().uuidString)")!),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addThisIPhone(defaultModel: nil)
        await model.refreshInstalled()
        XCTAssertTrue(model.onDevice.downloads.isEmpty)
        XCTAssertEqual(
            offers.map { model.isOnThisIPhone($0, of: phoneRepo) }, [true, true, false, false, false, false])
        XCTAssertFalse(model.isOnThisIPhone(small, of: MockLibrary.deskRepo), "another repository's variant is marked")

        let done = DownloadProgress(id: "", bytes: 1, total: 1, state: .done)
        let smallChoice = QuantChoice(repo: phoneRepo, quantization: small.label)
        let largeChoice = QuantChoice(repo: phoneRepo, quantization: large.label)
        model.onDevice.downloads = [smallChoice: done, largeChoice: done]
        await model.removeInstalled(try XCTUnwrap(model.onDevice.installed?.first { $0.quantization == "Q4_K_M" }))
        XCTAssertFalse(model.isOnThisIPhone(small, of: phoneRepo), "the variant removed is still marked")
        XCTAssertTrue(model.isOnThisIPhone(large, of: phoneRepo), "the variant left lost its mark")
        XCTAssertEqual(model.onDevice.downloads, [largeChoice: done], "the removal forgot another download")
    }
}
