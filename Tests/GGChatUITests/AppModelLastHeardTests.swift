import GGChatCore
import XCTest

@testable import GGChatUI

/// The model's clock, moved by the test.
final class HandClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// When each pipe's machine was last heard: stamped with the model's clock
/// when something the machine wrote arrives or the pipe changes between
/// connected and not, and never for what this side wrote.
final class AppModelLastHeardTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func makeModel(
        clock: HandClock, store: any Store = InMemoryStore(), sleeper: any Sleeper = ImmediateSleeper(),
        behind provider: any Provider = MockProvider(scripts: [.init(text: "over the pipe")])
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(sleeper: sleeper, provider: provider, registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelLastHeardTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults), now: { clock.now })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus?, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted { await Task.yield() }
    }

    /// Heard when the pipe connects, not when the dial goes out: a dial
    /// returns once the port here is bound, before the machine answers.
    @MainActor
    func testAPipeThatConnectsIsHeardThen() async throws {
        let clock = HandClock(start)
        let store = InMemoryStore()
        let sleeper = HeldSleeper()
        let (model, config) = try makeModel(clock: clock, store: store, sleeper: sleeper)
        await model.connectPipe(for: config)
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle)
        XCTAssertNil(model.lastHeard(for: config.id), "a dial still looking was heard")

        clock.now = start.addingTimeInterval(90)
        sleeper.release()
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.lastHeard(for: config.id), clock.now)
        XCTAssertEqual(try store.loadLastHeard(), [config.id: clock.now], "the time was not kept in the store")
    }

    /// A machine that goes quiet the way modelpipe reports it leaves the pipe
    /// looking. It was last heard when the pipe stopped being connected, and
    /// looking on after that adds nothing.
    @MainActor
    func testAPipeThatGoesQuietKeepsItsTime() async throws {
        let clock = HandClock(start)
        let (model, config) = try makeModel(clock: clock)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        let mock = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)

        let quietAt = start.addingTimeInterval(60)
        clock.now = quietAt
        mock.wentQuiet()
        await waitForStatus(.idle, model, config.id)
        XCTAssertEqual(model.lastHeard(for: config.id), quietAt)

        clock.now = start.addingTimeInterval(3600)
        mock.wentQuiet()
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle)
        XCTAssertEqual(model.lastHeard(for: config.id), quietAt, "a pipe still looking moved the time on")
    }

    /// `tunnel_unavailable` is this device's end of the pipe saying no
    /// tunnel is up, and a transport error is nothing from the machine
    /// either. A code the machine wrote is hearing, refusal or not.
    @MainActor
    func testARefusalWrittenOnThisSideIsNotHearing() async throws {
        let clock = HandClock(start)
        let noTunnel = ProviderError.server(
            status: 502, code: "tunnel_unavailable", message: "no tunnel to the serving side is connected right now")
        let behind = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "")], failure: noTunnel))
        let (model, config) = try makeModel(clock: clock, sleeper: HeldSleeper(), behind: behind)
        await model.connectPipe(for: config)
        model.newConversation()
        try await XCTUnwrap(model.send("anyone?")).value
        XCTAssertEqual(model.selectedConversation?.messages.last?.failure?.code, "tunnel_unavailable")
        XCTAssertNil(model.lastHeard(for: config.id), "this side's refusal was heard as the machine")

        behind.wrap(MockProvider(scripts: [.init(text: "a b c")], failAfterTokens: 0))
        try await XCTUnwrap(model.retry()).value
        XCTAssertNil(model.lastHeard(for: config.id), "a transport error was heard as the machine")

        clock.now = start.addingTimeInterval(30)
        behind.wrap(
            MockProvider(
                scripts: [.init(text: "")],
                failure: .server(status: 401, code: "invalid_api_key", message: "invalid or missing bearer token")))
        try await XCTUnwrap(model.retry()).value
        XCTAssertEqual(model.lastHeard(for: config.id), clock.now, "a refusal the machine wrote was not heard")
    }

    @MainActor
    func testAFinishedReplyIsHeard() async throws {
        let clock = HandClock(start)
        let (model, config) = try makeModel(clock: clock)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.lastHeard(for: config.id), start)

        clock.now = start.addingTimeInterval(45)
        model.newConversation()
        try await XCTUnwrap(model.send("hello")).value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "over the pipe")
        XCTAssertEqual(model.lastHeard(for: config.id), clock.now)
    }

    /// A model list and an answer about the status pane are the machine too.
    @MainActor
    func testAModelListAndAStatusAnswerAreHeard() async throws {
        let clock = HandClock(start)
        let host = "last-heard.test"
        ModelsServer.answer(.listing, at: host)
        let (model, config) = try makeModel(clock: clock, behind: ModelsServer.provider(at: host))
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)

        clock.now = start.addingTimeInterval(20)
        await model.refreshModels(for: config)
        XCTAssertEqual(model.models(for: config.id).map(\.id), ModelsServer.listed)
        XCTAssertEqual(model.lastHeard(for: config.id), clock.now, "a model list was not heard")

        clock.now = start.addingTimeInterval(40)
        await model.probeProxyStatus(for: config)
        XCTAssertEqual(ModelsServer.statusRequests(at: host), 1)
        XCTAssertEqual(model.lastHeard(for: config.id), clock.now, "a status answer was not heard")
    }

    /// The hang-up that follows a removal stops the pipe being connected,
    /// and must not stamp a time for a provider that is gone.
    @MainActor
    func testRemovingTheProviderForgetsWhenItWasHeard() async throws {
        let clock = HandClock(start)
        let store = InMemoryStore()
        let (model, config) = try makeModel(clock: clock, store: store)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertNotNil(model.lastHeard(for: config.id))

        clock.now = start.addingTimeInterval(10)
        model.removeProvider(config.id)
        await waitForStatus(nil, model, config.id)
        XCTAssertNil(model.pipeStatus(for: config.id), "the pipe was never hung up")
        XCTAssertNil(model.lastHeard(for: config.id))
        XCTAssertEqual(try store.loadLastHeard(), [:])
    }

    /// Settings says the time in the locale's short style, with the date in
    /// front when it was not today by the model's clock.
    @MainActor
    func testTheLineSaysTheTimeAndTheDateWhenItWasNotToday() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_GB")
        let morning = DateComponents(year: 2026, month: 9, day: 28, hour: 8, minute: 12)
        let heardAt = try XCTUnwrap(calendar.date(from: morning))
        let clock = HandClock(heardAt)
        let (model, config) = try makeModel(clock: clock)
        XCTAssertEqual(model.lastHeardLine(for: config.id, locale: locale, calendar: calendar), "not heard from yet")

        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        clock.now = heardAt.addingTimeInterval(12 * 3600)
        XCTAssertEqual(model.lastHeardLine(for: config.id, locale: locale, calendar: calendar), "last heard 08:12")
        clock.now = heardAt.addingTimeInterval(24 * 3600)
        XCTAssertEqual(
            model.lastHeardLine(for: config.id, locale: locale, calendar: calendar), "last heard 28/09/2026, 08:12")
    }
}
