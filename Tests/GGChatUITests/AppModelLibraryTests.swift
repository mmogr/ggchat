import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// The model browser, walked on `MockLibrary`: an opening reads the device
/// once and asks every verdict with that reading, a quantization too big for
/// the device is never downloaded, choosing a model adds This iPhone once,
/// and the browser says when it read the device. The library makes every
/// verdict; the app only asks.
@MainActor
final class AppModelLibraryTests: XCTestCase {
    private let phoneRepo = "mock/phone-1.7b-GGUF"
    private let deskRepo = "mock/desk-27b-GGUF"
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)
    /// 22:13:20 on 14 November 2023, in UTC.
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeModel(
        engine: any LocalEngine = MockEngine(registry: LoopbackProviderRegistry()),
        library: any ModelLibrary = RecordingLibrary()
    ) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelLibraryTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine, library: library, diagnostics: Diagnostics(defaults: defaults), now: { [stamp] in stamp })
    }

    /// Opens the browser with `reading`, counting the readings taken.
    private func open(
        _ model: AppModel, with reading: DeviceReading?, counting samples: inout Int
    ) throws
        -> ModelBrowser
    {
        model.openModelBrowser {
            samples += 1
            return reading
        }
        return try XCTUnwrap(model.onDevice.modelBrowser, "the browser did not open")
    }

    /// Waits until `done` holds, for `AppModelEngineTests.waitUntil`'s
    /// reason: a download is followed on a task of its own.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// One reading per opening: the suggestions, a search and two
    /// repositories' quantizations all go without another, and every verdict
    /// is asked with that one. The next opening reads again, and the first
    /// keeps its own.
    func testTheReadingIsSampledOncePerOpen() async throws {
        let library = RecordingLibrary()
        let model = makeModel(library: library)
        var samples = 0
        let browser = try open(model, with: reading, counting: &samples)
        XCTAssertEqual(samples, 1)
        XCTAssertEqual(browser.checkedAt, stamp)

        await model.loadSuggestions(in: browser)
        browser.query = "mock"
        await model.search(in: browser)
        await model.searchMore(in: browser)
        await model.loadOffers(of: phoneRepo, in: browser)
        await model.loadOffers(of: deskRepo, in: browser)
        XCTAssertEqual(samples, 1, "the browser read the device again while it was open")
        XCTAssertEqual(library.inner.readings.all, [reading, reading, reading])
        XCTAssertEqual(browser.suggestions?.count, 1)
        XCTAssertEqual(browser.offers[phoneRepo]?.count, 4)

        let later = DeviceReading(physicalBytes: 12 << 30, availableBytes: 2 << 30, isSimulator: false)
        let again = try open(model, with: later, counting: &samples)
        XCTAssertEqual(samples, 2, "opening again did not read the device again")
        XCTAssertFalse(again === browser)
        await model.loadOffers(of: phoneRepo, in: again)
        XCTAssertEqual(library.inner.readings.all.last, later)
        XCTAssertEqual(browser.reading, reading, "the first opening's reading changed under it")
    }

    /// A quantization gglib found too big is refused before the library
    /// hears of it, and This iPhone is not added for it. Every other verdict,
    /// "can't tell yet" included, may be downloaded.
    func testATooBigQuantizationCannotBeDownloaded() async throws {
        let library = RecordingLibrary()
        let model = makeModel(library: library)
        var samples = 0
        let browser = try open(model, with: reading, counting: &samples)
        await model.loadOffers(of: phoneRepo, in: browser)
        let offers = try XCTUnwrap(browser.offers[phoneRepo])
        XCTAssertEqual(offers.map(\.verdict.allowsDownload), [true, true, false, true])
        let tooBig = try XCTUnwrap(offers.first { !$0.verdict.allowsDownload })

        model.download(tooBig, of: phoneRepo)
        XCTAssertTrue(library.downloadsAsked.isEmpty, "a quantization too big for this iPhone was downloaded")
        XCTAssertTrue(model.providers.isEmpty, "This iPhone was added for a model it cannot run")
        XCTAssertNil(model.onDevice.downloads[QuantChoice(repo: phoneRepo, quantization: tooBig.name)])

        await model.loadOffers(of: deskRepo, in: browser)
        let desk = try XCTUnwrap(browser.offers[deskRepo])
        for offer in desk { model.download(offer, of: deskRepo) }
        XCTAssertTrue(library.downloadsAsked.isEmpty, "a desk model too big for this iPhone was downloaded")
    }

    /// The first model chosen adds This iPhone, with no model named until one
    /// is installed; the second finds it there. Each download is followed to
    /// done, and one under way or done is not started again.
    func testChoosingModelsCreatesThisIPhoneOnce() async throws {
        let library = RecordingLibrary()
        let model = makeModel(library: library)
        var samples = 0
        let browser = try open(model, with: reading, counting: &samples)
        await model.loadOffers(of: phoneRepo, in: browser)
        let offers = try XCTUnwrap(browser.offers[phoneRepo])
        let fits = try XCTUnwrap(offers.first { $0.name == "Q4_K_M" })
        let short = try XCTUnwrap(offers.first { $0.name == "Q8_0" })

        model.download(fits, of: phoneRepo)
        model.download(short, of: phoneRepo)
        model.download(fits, of: phoneRepo)
        XCTAssertEqual(model.providers.map(\.kind), [.onDevice])
        XCTAssertEqual(model.providers.first?.name, "This iPhone")
        XCTAssertNil(model.providers.first?.defaultModel, "a model not yet installed was named the default")

        let both = [fits, short].map { QuantChoice(repo: phoneRepo, quantization: $0.name) }
        let done = await waitUntil { both.allSatisfy { model.onDevice.downloads[$0] == .done } }
        XCTAssertTrue(done, "the downloads did not walk to done: \(model.onDevice.downloads)")
        model.download(fits, of: phoneRepo)
        XCTAssertEqual(library.downloadsAsked, ["\(phoneRepo):Q4_K_M", "\(phoneRepo):Q8_0"])
        XCTAssertEqual(model.providers.count, 1)
    }

    /// A download whose steps end short of done or failed, which a library
    /// keeping `download`'s contract never does, is kept as failed rather
    /// than left downloading for good, so it can be chosen again.
    func testADownloadThatStopsShortCanBeChosenAgain() async throws {
        let library = RecordingLibrary(endsShort: true)
        let model = makeModel(library: library)
        var samples = 0
        let browser = try open(model, with: reading, counting: &samples)
        await model.loadOffers(of: phoneRepo, in: browser)
        let fits = try XCTUnwrap(browser.offers[phoneRepo]?.first { $0.name == "Q4_K_M" })
        let choice = QuantChoice(repo: phoneRepo, quantization: fits.name)

        model.download(fits, of: phoneRepo)
        let failed = await waitUntil { model.onDevice.downloads[choice] == .failed(reason: AppModel.stoppedShort) }
        XCTAssertTrue(failed, "a download that stopped short was left at \(model.onDevice.downloads)")
        model.download(fits, of: phoneRepo)
        let again = await waitUntil { library.downloadsAsked.count == 2 }
        XCTAssertTrue(again, "a download that stopped short could not be chosen again: \(library.downloadsAsked)")
    }

    /// The browser says when it read the device, by the model's clock, and
    /// says so when it could not; with no reading, nothing that needs one is
    /// asked, and the sentence is said under the section.
    func testTheBrowserSaysWhenItReadTheDevice() async throws {
        let library = RecordingLibrary()
        let model = makeModel(library: library)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let locale = Locale(identifier: "en_GB")
        var samples = 0
        let browser = try open(model, with: reading, counting: &samples)
        XCTAssertEqual(
            model.checkedLine(for: browser, locale: locale, calendar: calendar), "Memory checked at 22:13")

        let unread = try open(model, with: nil, counting: &samples)
        XCTAssertEqual(model.checkedLine(for: unread, locale: locale, calendar: calendar), AppModel.unreadDevice)
        await model.loadSuggestions(in: unread)
        await model.loadOffers(of: phoneRepo, in: unread)
        XCTAssertEqual(unread.suggestionsFailure, AppModel.unreadDevice)
        XCTAssertEqual(unread.offerFailures[phoneRepo], AppModel.unreadDevice)
        XCTAssertTrue(library.inner.readings.all.isEmpty, "a verdict was asked with no reading")
    }

    /// A search starts afresh on each query, a page at a time, and a blank
    /// one clears what was found.
    func testASearchGoesOnAPageAtATime() async throws {
        let model = makeModel()
        var samples = 0
        let browser = try open(model, with: reading, counting: &samples)
        browser.query = "  mock "
        await model.search(in: browser)
        XCTAssertEqual(browser.hits.map(\.repo), [phoneRepo])
        XCTAssertNotNil(browser.nextCursor)
        await model.searchMore(in: browser)
        XCTAssertEqual(browser.hits.map(\.repo), [phoneRepo, deskRepo])
        XCTAssertNil(browser.nextCursor)

        browser.query = "desk"
        await model.search(in: browser)
        XCTAssertEqual(browser.hits.map(\.repo), [deskRepo])
        browser.query = " "
        await model.search(in: browser)
        XCTAssertTrue(browser.hits.isEmpty)
        XCTAssertNil(browser.searched)
    }

    /// A build with no engine opens no browser and downloads nothing, and a
    /// library that cannot answer says why under the section.
    func testWithNoEngineNothingIsBrowsedOrDownloaded() async throws {
        let library = RecordingLibrary()
        let model = makeModel(engine: UnavailableEngine(), library: library)
        XCTAssertFalse(model.runsModelsHere)
        model.openModelBrowser { reading }
        XCTAssertNil(model.onDevice.modelBrowser, "a build with no engine opened the browser")
        let offer = QuantOffer(
            name: "Q4_K_M", totalBytes: 1 << 30, shardCount: 1, verdict: .fits(ctx: 16_384),
            why: FitWhy(weightsBytes: nil, kvBytesPerToken: nil, budgetBytes: nil, trainedCtx: nil))
        model.download(offer, of: phoneRepo)
        XCTAssertTrue(library.downloadsAsked.isEmpty)
        XCTAssertTrue(model.providers.isEmpty)

        let unanswered = makeModel(library: UnavailableLibrary())
        var samples = 0
        let browser = try open(unanswered, with: reading, counting: &samples)
        await unanswered.loadSuggestions(in: browser)
        XCTAssertEqual(browser.suggestionsFailure, OnDeviceError.engineUnavailable.errorDescription)
    }

    /// The chip's few words for each verdict, which the walks look for.
    func testTheChipSaysEachVerdictInAFewWords() {
        XCTAssertEqual(FitChip.words(for: .fits(ctx: 16_384)), "Fits · 16K")
        XCTAssertEqual(FitChip.words(for: .tight(ctx: 4_096)), "Short context · 4K")
        XCTAssertEqual(FitChip.words(for: .tooBig(needBytes: 5 << 30, haveBytes: 3 << 30)), "Too big for this iPhone")
        XCTAssertEqual(FitChip.words(for: .unknown(missing: .kvShape)), "Can't tell yet")
        XCTAssertEqual(FitChip.context(512), "512")
    }

    /// The Why sheet has a sentence for each of the four figures, and says
    /// one gglib did not have is not known rather than reading it as zero.
    func testTheWhySheetSaysEachFigureOrThatItIsNotKnown() {
        let known = FitWhySheet.lines(
            FitWhy(weightsBytes: 1 << 30, kvBytesPerToken: 114_688, budgetBytes: 3 << 30, trainedCtx: 40_960))
        XCTAssertEqual(known.count, 4)
        XCTAssertFalse(known.contains { $0.contains("not known") }, "\(known)")
        XCTAssertTrue(known[0].hasPrefix("The weights take "))
        XCTAssertTrue(known[2].hasPrefix("This iPhone gives a model "))

        let partly = FitWhySheet.lines(
            FitWhy(weightsBytes: 1 << 29, kvBytesPerToken: nil, budgetBytes: 3 << 30, trainedCtx: nil))
        XCTAssertEqual(partly.filter { $0.contains("not known") }.count, 2, "\(partly)")
        XCTAssertFalse(partly.contains { $0.contains("Zero") || $0.contains(" 0 ") }, "\(partly)")

        XCTAssertTrue(FitWhySheet.verdictLine(.tight(ctx: 4_096)).contains("short context"))
        XCTAssertTrue(FitWhySheet.verdictLine(.unknown(missing: .kvShape)).contains("layers and attention heads"))
        XCTAssertTrue(FitWhySheet.verdictLine(.tooBig(needBytes: 5 << 30, haveBytes: 3 << 30)).contains("needs"))
    }
}
