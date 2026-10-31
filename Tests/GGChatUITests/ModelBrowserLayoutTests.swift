import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// How the browser is reached and what its rows say: This iPhone is a kind
/// in Add provider only where this build runs models here, and its page
/// presents no sheet of its own; a chip opens the sheet with what gglib said
/// of the model; each row's line, in few words; "On this iPhone" holding
/// the models installed and those on their way; and the question asked
/// before one is removed.
@MainActor
final class ModelBrowserLayoutTests: XCTestCase {
    private let none = FitWhy(weightsBytes: nil, kvBytesPerToken: nil, budgetBytes: nil, trainedCtx: nil)
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)

    private func makeModel(engine: any LocalEngine) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "ModelBrowserLayoutTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine, library: RecordingLibrary(), diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// Add provider offers This iPhone beside Server and Pipe only where
    /// this build runs models on this device, and first run names it only
    /// there; the Mac, and a build with no engine, keep the two kinds.
    func testThisIPhoneIsAKindOnlyWhereModelsRunHere() {
        XCTAssertEqual(AddProviderView.Kind.offered(runsModelsHere: true), [.server, .pipe, .thisIPhone])
        XCTAssertEqual(AddProviderView.Kind.offered(runsModelsHere: false), [.server, .pipe])
        XCTAssertEqual(AddProviderView.Kind.thisIPhone.rawValue, "This iPhone")
        XCTAssertTrue(EmptyDetailView.firstRun(runsModelsHere: true).contains("this iPhone"))
        XCTAssertFalse(EmptyDetailView.firstRun(runsModelsHere: false).contains("iPhone"))
    }

    /// This iPhone's page in Add provider is one opening of the browser,
    /// reading the device once, and presents nothing: the browser's own
    /// sheet is left for "Find a model…", so the two never stack. Where no
    /// model runs here, there is none.
    func testAddProvidersBrowserOpensNoSheetOfItsOwn() throws {
        let model = makeModel(engine: MockEngine(registry: LoopbackProviderRegistry()))
        var samples = 0
        let browser = try XCTUnwrap(
            model.makeModelBrowser {
                samples += 1
                return reading
            })
        XCTAssertEqual(samples, 1)
        XCTAssertEqual(browser.reading, reading)
        XCTAssertNil(model.onDevice.modelBrowser, "Add provider's page opened the browser's own sheet")

        let mac = makeModel(engine: UnavailableEngine())
        XCTAssertNil(mac.makeModelBrowser { reading }, "a build with no engine made a browser")
    }

    /// The sheet a chip opens says what gglib said of the model: a
    /// suggestion's verdict, its figures and gglib's sentence on why that
    /// one; a quantization's without a sentence; an installed model's
    /// verdict alone, with no figures to say a reading under. VoiceOver
    /// hears the chip's words and a hint, not a "Why".
    func testAChipsSheetSaysWhatGglibSaidOfTheModel() {
        let why = FitWhy(weightsBytes: 1 << 30, kvBytesPerToken: 114_688, budgetBytes: 3 << 30, trainedCtx: 40_960)
        let suggestion = Suggestion(
            repo: "Qwen/Qwen3-1.7B-GGUF", quantization: "Q4_K_M", bytes: 1_100_000_000, verdict: .fits(ctx: 16_384),
            why: why, rationale: "Small enough to leave room for a long chat.")
        let shown = FitExplanation(suggestion: suggestion)
        XCTAssertEqual(shown.rationale, "Small enough to leave room for a long chat.")
        XCTAssertEqual(shown.why, why)
        XCTAssertEqual(shown.verdict, .fits(ctx: 16_384))
        XCTAssertEqual(shown.repo, "Qwen/Qwen3-1.7B-GGUF")
        XCTAssertEqual(shown.name, "Q4_K_M")

        var silent = suggestion
        silent.rationale = ""
        XCTAssertNil(FitExplanation(suggestion: silent).rationale, "an empty sentence took a section")

        let offer = QuantOffer(name: "Q8_0", totalBytes: 2 << 30, shardCount: 1, verdict: .tight(ctx: 4_096), why: why)
        let quant = FitExplanation(repo: "Qwen/Qwen3-1.7B-GGUF", offer: offer)
        XCTAssertNil(quant.rationale)
        XCTAssertEqual(quant.why, why)

        let installed = InstalledModel(
            id: 7, name: "Qwen3-0.6B-Q4_K_M", bytes: 397_000_000, trainedCtx: nil, capabilities: [],
            verdict: .fits(ctx: 32_768))
        let mine = FitExplanation(installed: installed)
        XCTAssertNil(mine.why, "an installed model was given figures the library did not send")
        XCTAssertNil(mine.repo)

        XCTAssertEqual(FitChip.hint, "Shows how gglib judged it.")
        XCTAssertFalse(FitChip.hint.contains("Why"))
        XCTAssertFalse(FitChip.words(for: .fits(ctx: 16_384)).contains("Why"))
    }

    /// Each row's line in few words: a suggestion's quantization and size;
    /// a hit's model and owner apart, and its size, context and downloads,
    /// leaving out what Hugging Face does not say; a quantization's size,
    /// and its files when it is split; how far a download has come.
    func testEachRowSaysItsLineInFewWords() {
        let suggestion = Suggestion(
            repo: "Qwen/Qwen3-1.7B-GGUF", quantization: "Q4_K_M", bytes: 1_100_000_000, verdict: .fits(ctx: 16_384),
            why: none, rationale: "")
        XCTAssertEqual(SuggestionRow.detail(suggestion), "Q4_K_M · \(Sizes.download(1_100_000_000))")

        XCTAssertEqual(RepoName.model("Qwen/Qwen3-1.7B-GGUF"), "Qwen3-1.7B-GGUF")
        XCTAssertEqual(RepoName.owner("Qwen/Qwen3-1.7B-GGUF"), "Qwen")
        XCTAssertEqual(RepoName.model("loose"), "loose")
        XCTAssertNil(RepoName.owner("loose"))

        let locale = Locale(identifier: "en_US")
        let full = SearchHit(
            repo: "Qwen/Qwen3-1.7B-GGUF", likes: 3, downloads: 9_400, parametersB: 1.7, trainedCtx: 40_960)
        XCTAssertEqual(HitRow.detail(full, locale: locale), "1.7B · 40K context · 9,400 downloads")
        let bare = SearchHit(repo: "someone/thing", likes: 0, downloads: 12, parametersB: nil, trainedCtx: nil)
        XCTAssertEqual(HitRow.detail(bare, locale: locale), "12 downloads")

        let whole = QuantOffer(
            name: "Q4_K_M", totalBytes: 1_100_000_000, shardCount: 1, verdict: .tooBig(needBytes: 1, haveBytes: 0),
            why: none)
        XCTAssertEqual(ModelBrowserRepoView.title(whole), "Q4_K_M · \(Sizes.download(1_100_000_000))")
        let split = QuantOffer(
            name: "Q8_0", totalBytes: 4_290_000_000, shardCount: 2, verdict: .fits(ctx: 8_192), why: none)
        XCTAssertEqual(ModelBrowserRepoView.title(split), "Q8_0 · \(Sizes.download(4_290_000_000)) in 2 files")

        XCTAssertEqual(DownloadBar.percent(DownloadProgress(id: "", bytes: 41, total: 100, state: .running)), "41%")
        XCTAssertEqual(DownloadBar.percent(DownloadProgress(id: "", bytes: 120, total: 100, state: .running)), "100%")
        XCTAssertNil(DownloadBar.percent(DownloadProgress(id: "", bytes: 41, total: nil, state: .running)))
    }

    /// "On this iPhone" holds the models installed, as the library lists
    /// them, then the downloads on their way, paused ones too, in order of
    /// repository and quantization; one done or failed is not on its way,
    /// and before the library has listed anything the downloads are there
    /// alone.
    func testOnThisIPhoneHoldsTheInstalledAndTheDownloadsOnTheirWay() {
        let installed = [
            InstalledModel(id: 2, name: "b", bytes: 1, trainedCtx: nil, capabilities: [], verdict: .fits(ctx: 4_096)),
            InstalledModel(id: 1, name: "a", bytes: 1, trainedCtx: nil, capabilities: [], verdict: .fits(ctx: 4_096)),
        ]
        func step(_ state: DownloadState) -> DownloadProgress {
            DownloadProgress(id: "", bytes: 1, total: 10, state: state)
        }
        let running = QuantChoice(repo: "z/model", quantization: "Q4_K_M")
        let paused = QuantChoice(repo: "a/model", quantization: "Q8_0")
        let downloads = [
            running: step(.running),
            paused: step(.paused),
            QuantChoice(repo: "a/model", quantization: "F16"): step(.done),
            QuantChoice(repo: "b/model", quantization: "Q2_K"): step(.failed(reason: "no")),
        ]

        let rows = OnThisIPhoneRow.rows(installed: installed, downloads: downloads)
        XCTAssertEqual(
            rows,
            [
                .installed(installed[0]), .installed(installed[1]),
                .downloading(paused, step(.paused)), .downloading(running, step(.running)),
            ])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "two rows share an id")

        XCTAssertEqual(
            OnThisIPhoneRow.rows(installed: nil, downloads: [running: step(.queued)]),
            [.downloading(running, step(.queued))])
        XCTAssertTrue(OnThisIPhoneRow.rows(installed: [], downloads: [:]).isEmpty)
    }

    /// Every way of removing a model asks first, naming the model and the
    /// room its removal frees.
    func testTheRemovalQuestionNamesTheModelAndTheRoomItFrees() {
        let item = InstalledModel(
            id: 1, name: "mock-phone-1.7b", bytes: 1_073_741_824, trainedCtx: nil, capabilities: [],
            verdict: .fits(ctx: 4_096))
        XCTAssertEqual(OnThisIPhoneSection.removalQuestion(for: item), "Remove mock-phone-1.7b?")
        XCTAssertEqual(OnThisIPhoneSection.removalDetail(for: item), "This frees 1.07 GB on this iPhone.")
    }

    /// A model already on this iPhone while there is no This iPhone, as
    /// after it was removed, is used by adding This iPhone with that model
    /// chosen; once This iPhone is there, Use changes nothing, its model
    /// being chosen in a conversation. A build with no engine adds nothing.
    func testUseAddsThisIPhoneWithThatModelOnlyWhileThereIsNone() {
        let first = InstalledModel(
            id: 1, name: "mock-phone-1.7b", bytes: 1, trainedCtx: nil, capabilities: [], verdict: .fits(ctx: 4_096))
        let second = InstalledModel(
            id: 2, name: "other-0.6b", bytes: 1, trainedCtx: nil, capabilities: [], verdict: .fits(ctx: 4_096))
        let model = makeModel(engine: MockEngine(registry: LoopbackProviderRegistry()))
        XCTAssertNil(model.thisIPhoneID)

        model.useInstalled(first)
        XCTAssertEqual(model.providers.map(\.kind), [.onDevice])
        XCTAssertEqual(model.providers.first?.name, "This iPhone")
        XCTAssertEqual(model.providers.first?.defaultModel, "mock-phone-1.7b")

        model.useInstalled(second)
        XCTAssertEqual(model.providers.count, 1, "Use added a second This iPhone")
        XCTAssertEqual(model.providers.first?.defaultModel, "mock-phone-1.7b", "Use changed This iPhone's model")

        let mac = makeModel(engine: UnavailableEngine())
        mac.useInstalled(first)
        XCTAssertTrue(mac.providers.isEmpty, "a build with no engine added This iPhone")
    }
}
