import GGChatCore
import XCTest

@testable import GGChatUI

/// A send waiting for its pipe ends, short of the pipe connecting or its
/// dial being refused, in three ways: Stop, the app going to the background,
/// and the provider's removal. None is a failure.
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

    /// Waits, for up to `limit`, until `done` holds, and answers whether it
    /// did. Polled on a clock rather than counted in yields, for
    /// `GatedConnector.waitForArrivals`'s reason: a removal hangs its pipe up
    /// in a task of its own, and a loaded machine can keep that task waiting
    /// for a thread for longer than any count of yields.
    @MainActor
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
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
        let dialled = await gate.waitForArrivals(1)
        XCTAssertTrue(dialled, "a pipe never dialled was not dialled")
        XCTAssertEqual(gate.arrivals, 1, "the wait dialled the pipe more than once")

        model.stop()
        await settle(send, model)
        try assertLeftWithRetry(model, "a stop while waiting")

        let retried = try XCTUnwrap(model.retry(), "Retry was not offered after a stop")
        gate.open()
        await settle(retried, model)
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(gate.arrivals, 1, "the stop called the dial off, or Retry dialled again")
    }

    /// The background puts the wait down as it puts a reply down.
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
        let dialled = await gate.waitForArrivals(1)
        XCTAssertTrue(dialled, "the wait never dialled its pipe")

        model.removeProvider(config.id)
        let ended = await waitUntil { !model.isStreaming }
        XCTAssertTrue(ended, "the wait went on after its provider was removed")
        try assertLeftWithRetry(model, "a removal while waiting")

        // The removal hangs the pipe up in a task of its own, once the reply
        // it put down has finished. A dial that lands before that task has
        // moved the dial generation on is installed, and then hung up by it,
        // so what is waited for is the end of both: landed, unbound, and no
        // longer the provider's.
        gate.open()
        let bound = { gate.sessions.map(\.baseURL).filter { registry.provider(for: $0) != nil } }
        let settled = await waitUntil {
            !gate.sessions.isEmpty && bound().isEmpty && model.pipeSession(for: config.id) == nil
        }
        XCTAssertTrue(settled, "the dial never landed and was hung up")
        XCTAssertEqual(gate.sessions.count, 1, "the held dial never landed")
        XCTAssertEqual(bound(), [], "the dial landed for a removed provider and kept its port")
        XCTAssertNil(model.pipeSession(for: config.id))
    }
}
