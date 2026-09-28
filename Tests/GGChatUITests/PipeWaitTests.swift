import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A dial held until it is let go, and then refused the way a port that is
/// taken refuses it.
private final class HeldRefusal: PipeConnector {
    private let released = Mutex(false)
    private let arrived = Mutex(0)

    /// How many dials have gone out, refused yet or not.
    var arrivals: Int {
        arrived.withLock { $0 }
    }

    func release() {
        released.withLock { $0 = true }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        arrived.withLock { $0 += 1 }
        while !released.withLock({ $0 }) { await Task.yield() }
        throw PipeConnectError.dialFailed(message: "The port is taken.", retryable: true)
    }

    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        throw PipeConnectError.unavailable
    }
}

/// A send, a Retry or a Continue through a pipe that is not connected waits
/// for it, joining the dial in flight or starting one, and streams once it
/// connects.
final class PipeWaitTests: XCTestCase {
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

    /// A model holding one pipe, "home", with a conversation open on it.
    @MainActor
    private func makeModel(
        clock: HandClock, connector: (LoopbackProviderRegistry) -> any PipeConnector
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "PipeWaitTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector(registry), diagnostics: Diagnostics(defaults: defaults), now: { clock.now })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        model.newConversation()
        return (model, config)
    }

    /// The line the reply in flight shows while it waits.
    @MainActor
    private func waitingLine(_ model: AppModel) -> String? {
        model.liveReply.flatMap { model.waitingLine(for: $0, locale: locale, calendar: calendar) }
    }

    /// Waits, for a bounded number of turns, for the reply in flight to end,
    /// then calls it off if it has not, so a wait that never ends fails here
    /// rather than hanging the suite.
    @MainActor
    private func settle(_ task: Task<Void, Never>, _ model: AppModel) async {
        for _ in 0..<10_000 where model.isStreaming { await Task.yield() }
        XCTAssertFalse(model.isStreaming, "the reply in flight never ended")
        task.cancel()
        await task.value
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus?, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted { await Task.yield() }
    }

    /// The dial the conversation's opening sent is joined, not repeated, and
    /// the reply streams once the pipe connects. The opening's dial is not a
    /// quiet one, and nothing is raised.
    @MainActor
    func testASendDuringADialWaitsForItThenStreamsWithNoAlert() async throws {
        var made: GatedConnector?
        let (model, config) = try makeModel(clock: HandClock(morning)) { registry in
            let gate = GatedConnector(registry: registry)
            made = gate
            return gate
        }
        let gate = try XCTUnwrap(made)
        let opening = model.open(config)
        for _ in 0..<200 where gate.arrivals < 1 { await Task.yield() }

        let send = try XCTUnwrap(model.send("anyone?"), "a send through a pipe still dialling was refused")
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(model.liveReply?.waitingFor, config.id)
        XCTAssertEqual(waitingLine(model), "Waiting for home · not heard from yet")
        XCTAssertEqual(gate.arrivals, 1, "the send dialled again instead of joining the dial in flight")
        XCTAssertNil(model.lastError)

        gate.open()
        await settle(send, model)
        await opening.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.last?.content, MockProvider.sampleScript.text)
        XCTAssertEqual(messages.last?.isPartial, false)
        XCTAssertNil(model.lastError, "a send that waited raised an alert")
        XCTAssertEqual(gate.arrivals, 1)
    }

    /// A pipe that is closed, with nothing dialling it, is dialled by the
    /// send, and the line names when its machine was last heard.
    @MainActor
    func testASendOnAClosedPipeDialsIt() async throws {
        let clock = HandClock(morning)
        var made: GatedConnector?
        let (model, config) = try makeModel(clock: clock) { registry in
            let gate = GatedConnector(registry: registry)
            made = gate
            return gate
        }
        let gate = try XCTUnwrap(made)
        gate.release(1)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        await model.disconnectPipe(for: config.id, leaving: .closed)
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)

        clock.now = morning.addingTimeInterval(2 * 3600)
        let send = try XCTUnwrap(model.send("anyone?"), "a send through a closed pipe was refused")
        for _ in 0..<200 where gate.arrivals < 2 { await Task.yield() }
        XCTAssertEqual(gate.arrivals, 2, "the send did not dial the closed pipe")
        XCTAssertEqual(waitingLine(model), "Waiting for home · last heard 08:12")

        gate.open()
        await settle(send, model)
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, MockProvider.sampleScript.text)
        XCTAssertNil(model.lastError)
    }

    /// The dial's own sentence goes on the question, and not into an alert,
    /// even from a dial that is not quiet.
    @MainActor
    func testARefusedDialPutsItsSentenceOnTheQuestion() async throws {
        var made: HeldRefusal?
        let (model, config) = try makeModel(clock: HandClock(morning)) { _ in
            let refusing = HeldRefusal()
            made = refusing
            return refusing
        }
        let refusing = try XCTUnwrap(made)
        let opening = model.open(config)
        for _ in 0..<200 where refusing.arrivals < 1 { await Task.yield() }
        let send = try XCTUnwrap(model.send("anyone?"))
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(model.liveReply?.waitingFor, config.id)

        refusing.release()
        await settle(send, model)
        await opening.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertEqual(messages[0].failure?.message, "The port is taken.")
        XCTAssertNil(messages[0].failure?.hint, "a side to look at was made up for a sentence that named none")
        XCTAssertNil(model.lastError, "the refusal was raised as an alert as well")
        XCTAssertFalse(model.isStreaming)
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)
        XCTAssertEqual(refusing.arrivals, 1, "the send dialled again instead of joining the dial in flight")
    }

    /// Continue waits as a send does, and carries on the same partial once
    /// the pipe is back.
    @MainActor
    func testContinueWaitsForAPipeThatWentQuiet() async throws {
        let behind = RecordingProvider(wrapping: HangingProvider())
        let (model, config) = try makeModel(clock: HandClock(morning)) { registry in
            MockPipeConnector(sleeper: ImmediateSleeper(), provider: behind, registry: registry)
        }
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        let first = try XCTUnwrap(model.send("go"))
        for _ in 0..<200 where model.liveReply?.content.isEmpty != false { await Task.yield() }
        model.stop()
        await first.value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "half ")

        try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession).wentQuiet()
        await waitForStatus(.idle, model, config.id)
        behind.wrap(MockProvider(scripts: [.init(text: "and the rest")]))
        let resumed = try XCTUnwrap(model.continueReply(), "Continue was refused on a pipe that went quiet")
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(model.liveReply?.waitingFor, config.id)
        XCTAssertEqual(behind.requests.count, 1, "Continue asked a pipe that was still looking")

        await model.reconnectPipe(for: config)
        await settle(resumed, model)
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.content, "half and the rest")
        XCTAssertFalse(last.isPartial)
        XCTAssertEqual(behind.requests.count, 2)
    }
}
