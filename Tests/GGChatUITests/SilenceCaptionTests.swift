import GGChatCore
import XCTest

@testable import GGChatUI

/// A dial that never lands, the way a port that is taken refuses it.
private struct RefusingConnector: PipeConnector {
    func connect(ticket: String, token: String) async throws -> any PipeSession {
        throw PipeConnectError.dialFailed(message: "The port is taken.", retryable: true)
    }

    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        throw PipeConnectError.unavailable
    }
}

/// The line under the pill that names a machine that is not answering. It
/// waits for the machine to fail to answer, so the second or two a pipe
/// spends looking on every return to the foreground never shows it.
final class SilenceCaptionTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let locale = Locale(identifier: "en_GB")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// 08:12 on 28 September 2026, in UTC.
    private var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 8, minute: 12)) ?? .distantPast
    }

    @MainActor
    private func makeModel(
        clock: HandClock, connector: (LoopbackProviderRegistry) -> any PipeConnector
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "SilenceCaptionTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector(registry), diagnostics: Diagnostics(defaults: defaults), now: { clock.now })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        model.newConversation()
        return (model, config)
    }

    @MainActor
    private func caption(_ model: AppModel) throws -> String? {
        model.silenceCaption(for: try XCTUnwrap(model.selectedConversation), locale: locale, calendar: calendar)
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus?, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted { await Task.yield() }
    }

    /// A first dial looking, the app's own hang-up on the way to the
    /// background, and the dial again on the way back, held open while it
    /// looks: none of them is the machine failing to answer.
    @MainActor
    func testTheCaptionStaysAwayWhileAPipeReconnects() async throws {
        let clock = HandClock(morning)
        var gate: GatedConnector?
        let (model, config) = try makeModel(clock: clock) { registry in
            let made = GatedConnector(registry: registry)
            gate = made
            return made
        }
        let held = try XCTUnwrap(gate)
        let first = Task { await model.connectPipe(for: config) }
        await waitForStatus(.idle, model, config.id)
        XCTAssertNil(try caption(model), "a first dial still looking")
        held.release(1)
        await first.value
        await waitForStatus(.direct, model, config.id)
        XCTAssertNil(try caption(model))

        await model.scene(.background).value
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)
        XCTAssertNil(try caption(model), "the app's own hang-up")

        let resume = model.scene(.foreground)
        await waitForStatus(.idle, model, config.id)
        XCTAssertEqual(held.arrivals, 2, "the resume did not dial again")
        XCTAssertNil(try caption(model), "a reconnect still looking")
        held.open()
        await resume.value
        await waitForStatus(.direct, model, config.id)
        XCTAssertNil(try caption(model))
    }

    /// modelpipe leaves the pipe of a machine that went quiet looking, and
    /// never closes it. That is a connection that was up and was lost, and
    /// the caption stays until the pipe connects again.
    @MainActor
    func testTheCaptionShowsWhenAConnectedPipeGoesQuietUntilItConnects() async throws {
        let clock = HandClock(morning)
        let (model, config) = try makeModel(clock: clock) { registry in
            MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry)
        }
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        clock.now = morning.addingTimeInterval(28 * 60)
        try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession).wentQuiet()
        await waitForStatus(.idle, model, config.id)
        XCTAssertEqual(try caption(model), "home · last heard 08:40")

        await model.scene(.background).value
        XCTAssertEqual(try caption(model), "home · last heard 08:40", "a hang-up hid a machine that was not answering")
        clock.now = morning.addingTimeInterval(60 * 60)
        await model.scene(.foreground).value
        await waitForStatus(.direct, model, config.id)
        XCTAssertNil(try caption(model), "the machine answered and the caption stayed")
    }

    /// A pipe that closes on its own, and a dial that fails.
    @MainActor
    func testTheCaptionShowsWhenThePipeClosesOrTheDialFails() async throws {
        let clock = HandClock(morning)
        let (model, config) = try makeModel(clock: clock) { registry in
            MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry)
        }
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession).dropped()
        await waitForStatus(.closed, model, config.id)
        XCTAssertEqual(try caption(model), "home · last heard 08:12")

        let (refused, refusedConfig) = try makeModel(clock: clock) { _ in RefusingConnector() }
        await refused.connectPipe(for: refusedConfig, quietly: true)
        XCTAssertEqual(refused.pipeStatus(for: refusedConfig.id), .closed)
        XCTAssertEqual(try caption(refused), "home · not heard from yet")
        refused.removeProvider(refusedConfig.id)
        XCTAssertEqual(refused.unanswered, [], "a removed provider is still marked")
    }

    /// Only a pipe has a machine to hear from. A server added by address that
    /// answers is not stamped, and one that sends the refusal's code is not
    /// marked.
    @MainActor
    func testAServerAddedByAddressIsNeitherHeardNorMarked() async throws {
        var shared: LoopbackProviderRegistry?
        let (model, _) = try makeModel(clock: HandClock(morning)) { registry in
            shared = registry
            return MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry)
        }
        let registry = try XCTUnwrap(shared)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49997/v1"))
        let server = ProviderConfig(name: "desk", kind: .openAICompatible(baseURL: url), defaultModel: "mock-27b")
        try model.addProvider(server, credentials: [:])
        var conversation = model.newConversation()
        conversation.providerID = server.id
        model.update(conversation)

        registry.register(MockProvider(scripts: [.init(text: "fine")]), at: url)
        try await XCTUnwrap(model.send("hello")).value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "fine")
        XCTAssertNil(model.lastHeard(for: server.id), "a server added by address was heard")

        let noTunnel = ProviderError.server(status: 502, code: "tunnel_unavailable", message: "no tunnel")
        registry.register(MockProvider(scripts: [.init(text: "")], failure: noTunnel), at: url)
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(model.selectedConversation?.messages.last?.failure?.code, "tunnel_unavailable")
        XCTAssertEqual(model.unanswered, [], "a server added by address was marked")
    }

    /// A pipe that has never connected reads as looking, like any dial. A
    /// request through it that this side refuses because no tunnel is up is
    /// the machine failing to answer, until the pipe connects. A send is not
    /// such a request: it waits for the pipe instead. The same refusal under
    /// a connected pill does not contradict the pill.
    @MainActor
    func testTheCaptionShowsWhenARequestFindsNoTunnel() async throws {
        let clock = HandClock(morning)
        let host = "no-tunnel.caption.test"
        ModelsServer.answer(.refusing, at: host)
        let sleeper = HeldSleeper()
        let (model, config) = try makeModel(clock: clock) { registry in
            MockPipeConnector(sleeper: sleeper, provider: ModelsServer.provider(at: host), registry: registry)
        }
        await model.connectPipe(for: config)
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle)
        XCTAssertNil(try caption(model), "a dial still looking")

        await model.refreshModels(for: config, quietly: true)
        XCTAssertEqual(try caption(model), "home · not heard from yet")

        let send = try XCTUnwrap(model.send("anyone?"))
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 1, "the send asked a pipe that was still looking")
        XCTAssertNil(model.selectedConversation?.messages.last?.failure, "the send was refused instead of waiting")

        sleeper.release()
        for _ in 0..<5_000 where model.isStreaming { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertFalse(model.isStreaming, "the send went on waiting once the pipe connected")
        send.cancel()
        await send.value
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.selectedConversation?.messages.last?.failure?.code, "tunnel_unavailable")
        XCTAssertNil(try caption(model), "a caption under a pill that reads Direct")
    }
}
