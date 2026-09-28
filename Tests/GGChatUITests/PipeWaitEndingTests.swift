import GGChatCore
import XCTest

@testable import GGChatUI

/// A send waiting for its pipe ends, short of the pipe connecting or its
/// dial being refused, in three ways: Stop, the app going to the background,
/// and the provider's removal. None is a failure, and none is counted.
final class PipeWaitEndingTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// A model holding one pipe, "home", with a conversation open on it.
    @MainActor
    private func makeModel(
        connector: (LoopbackProviderRegistry) -> any PipeConnector
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "PipeWaitEndingTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector(registry), diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        model.newConversation()
        return (model, config)
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

    /// The question is left as it was asked, with no reply under it and no
    /// sentence on it, which is what draws Retry.
    @MainActor
    private func assertLeftWithRetry(_ model: AppModel, _ message: String) throws {
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user], message)
        XCTAssertNil(messages[0].failure, message)
        XCTAssertFalse(model.isStreaming, message)
        XCTAssertNil(model.lastError, message)
    }

    /// Stop ends the wait and leaves the dial it started to land. Retry asks
    /// again, joins that dial, and streams.
    @MainActor
    func testStopWhileWaitingLeavesRetryAndNoFailure() async throws {
        var made: GatedConnector?
        let (model, _) = try makeModel { registry in
            let gate = GatedConnector(registry: registry)
            made = gate
            return gate
        }
        let gate = try XCTUnwrap(made)
        let send = try XCTUnwrap(model.send("anyone?"))
        for _ in 0..<200 where gate.arrivals < 1 { await Task.yield() }
        XCTAssertEqual(gate.arrivals, 1, "a pipe never dialled was not dialled")

        model.stop()
        await settle(send, model)
        try assertLeftWithRetry(model, "a stop while waiting")

        let retried = try XCTUnwrap(model.retry(), "Retry was not offered after a stop")
        gate.open()
        await settle(retried, model)
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(gate.arrivals, 1, "the stop called the dial off, or Retry dialled again")
    }

    /// The background puts the wait down as it puts a reply down, and the
    /// close that follows is not one mid-reply: nothing had arrived.
    @MainActor
    func testABackgroundWhileWaitingLeavesRetryAndNoFailure() async throws {
        let sleeper = HeldSleeper()
        let (model, config) = try makeModel { registry in
            MockPipeConnector(sleeper: sleeper, registry: registry)
        }
        await model.connectPipe(for: config)
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle, "the pipe should still be looking")
        let send = try XCTUnwrap(model.send("anyone?"))
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(model.liveReply?.waitingFor, config.id)

        await model.scene(.background).value
        await send.value
        try assertLeftWithRetry(model, "a background while waiting")
        XCTAssertEqual(model.diagnostics.closedTransitions, 1)
        XCTAssertEqual(model.diagnostics.closedWhileStreaming, 0, "a close while waiting was counted as mid-reply")
    }

    /// Removing the provider ends its wait, and the dial the wait started
    /// hangs itself up when it lands.
    @MainActor
    func testRemovingTheProviderEndsTheWait() async throws {
        var made: (gate: GatedConnector, registry: LoopbackProviderRegistry)?
        let (model, config) = try makeModel { registry in
            let gate = GatedConnector(registry: registry)
            made = (gate, registry)
            return gate
        }
        let (gate, registry) = try XCTUnwrap(made)
        let send = try XCTUnwrap(model.send("anyone?"))
        defer { send.cancel() }
        for _ in 0..<200 where gate.arrivals < 1 { await Task.yield() }

        model.removeProvider(config.id)
        for _ in 0..<200 where model.isStreaming { await Task.yield() }
        try assertLeftWithRetry(model, "a removal while waiting")

        gate.open()
        let bound = { gate.sessions.map(\.baseURL).filter { registry.provider(for: $0) != nil } }
        for _ in 0..<200 where gate.sessions.isEmpty || !bound().isEmpty { await Task.yield() }
        XCTAssertEqual(gate.sessions.count, 1, "the held dial never landed")
        XCTAssertEqual(bound(), [], "the dial landed for a removed provider and kept its port")
        XCTAssertNil(model.pipeSession(for: config.id))
    }
}
