import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// gglib lists every variant a repository publishes and says what each one
/// is: the model browser offers the models alone, and Download refuses a
/// draft, a helper or a projector before the library hears of it.
@MainActor
final class ModelBrowserVariantTests: XCTestCase {
    private let phoneRepo = "mock/phone-1.7b-GGUF"
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)

    /// gglib lists a repository's projector and its draft beside its models,
    /// and fetches neither on its own: the browser keeps only the models, and
    /// a draft or a projector handed to Download is refused before the
    /// library hears of it, adding no This iPhone.
    func testADraftOrAProjectorIsNeverOffered() async throws {
        let library = RecordingLibrary()
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: MockEngine(registry: registry), library: library,
            diagnostics: Diagnostics(
                defaults: UserDefaults(suiteName: "ModelBrowserVariantTests.\(UUID().uuidString)")!),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        model.openModelBrowser { [reading] in reading }
        let browser = try XCTUnwrap(model.onDevice.modelBrowser, "the browser did not open")
        await model.loadOffers(of: phoneRepo, in: browser)
        let all = try await library.quantizations(repo: phoneRepo, reading: reading)
        XCTAssertEqual(all.map(\.role), [.model, .model, .model, .model, .projector, .draftOrHelper])
        XCTAssertEqual(browser.offers[phoneRepo]?.map(\.label), ["Q4_K_M", "Q8_0", "F16", "IQ2_XS"])

        for offer in all where offer.role != .model {
            XCTAssertFalse(offer.allowsDownload, "\(offer.label) may be downloaded")
            model.download(offer, of: phoneRepo)
        }
        XCTAssertTrue(library.downloadsAsked.isEmpty, "a draft or a projector was downloaded")
        XCTAssertTrue(model.providers.isEmpty, "This iPhone was added for a variant it cannot run")
    }
}
