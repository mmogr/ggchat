import GGChatCore
import XCTest

@testable import GGChatUI

/// Two sends waiting for the same pipe (ADR 0006, ADR 0012): the pipe is
/// dialled once for both, both stream once it is up, and a dial that is
/// refused says why under both questions.
final class ConcurrentPipeWaitTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(
        _ connector: any PipeConnector, registry: LoopbackProviderRegistry
    ) throws -> (
        AppModel, ProviderConfig
    ) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ConcurrentPipeWaitTests.\(UUID().uuidString)"))
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let home = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(home, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, home)
    }

    /// Sends in two new conversations on the model's one provider.
    @MainActor
    private func sendTwice(_ model: AppModel) throws -> [(UUID, Task<Void, Never>)] {
        var sent: [(UUID, Task<Void, Never>)] = []
        for _ in 0..<2 {
            let conversation = model.newConversation()
            sent.append((conversation.id, try XCTUnwrap(model.send("anyone?"), "the send was refused")))
        }
        return sent
    }

    @MainActor
    func testTwoSendsWaitingOnOnePipeDialItOnceAndBothStream() async throws {
        let registry = LoopbackProviderRegistry()
        let connector = GatedConnector(registry: registry)
        let (model, home) = try makeModel(connector, registry: registry)

        let sent = try sendTwice(model)
        let ids = sent.map(\.0)
        let dialled = await connector.waitForArrivals(1)
        XCTAssertTrue(dialled, "nothing dialled")
        for _ in 0..<200 where !ids.allSatisfy({ model.liveReplies[$0]?.waitingFor == home.id }) {
            await Task.yield()
        }
        for id in ids { XCTAssertEqual(model.liveReplies[id]?.waitingFor, home.id, "a send never waited") }
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(connector.arrivals, 1, "the second wait dialled the pipe as well")

        connector.open()
        for (_, task) in sent { await task.value }
        for id in ids {
            let messages = model.conversations.first { $0.id == id }?.messages ?? []
            XCTAssertEqual(messages.map(\.role), [.user, .assistant], "a waiting send never streamed")
        }
        XCTAssertTrue(model.pipeWaits.isEmpty)
    }

    /// A pipe that closed while still installed is hung up before it is
    /// dialled again. Two sends waiting on it do that once between them: a
    /// second hang-up, landing while the first send's dial is out, would call
    /// that dial off.
    @MainActor
    func testTwoSendsWaitingOnAClosedPipeHangItUpOnce() async throws {
        let registry = LoopbackProviderRegistry()
        let connector = HeldShutdownConnector(registry: registry)
        let (model, home) = try makeModel(connector, registry: registry)
        await model.connectPipe(for: home)
        for _ in 0..<200 where model.pipeStatus(for: home.id) != .direct { await Task.yield() }
        try XCTUnwrap(connector.mockSessions.first).forceClosed()
        for _ in 0..<200 where model.pipeStatus(for: home.id) != .closed { await Task.yield() }
        XCTAssertNotNil(model.pipeSession(for: home.id), "the closed pipe should still be installed")

        let sent = try sendTwice(model)
        for _ in 0..<500 where connector.shutdownsStarted == 0 { await Task.yield() }
        for _ in 0..<500 { await Task.yield() }
        XCTAssertEqual(connector.shutdownsStarted, 1, "two waiting sends hung the pipe up twice")

        connector.release()
        for (_, task) in sent { await task.value }
        for (id, _) in sent {
            let messages = model.conversations.first { $0.id == id }?.messages ?? []
            XCTAssertEqual(messages.map(\.role), [.user, .assistant], "a waiting send never streamed")
        }
    }

    @MainActor
    func testARefusedDialSaysWhyUnderBothQuestions() async throws {
        let registry = LoopbackProviderRegistry()
        let connector = SwitchedConnector(registry: registry, pairings: MockPairings(outcome: .success("key")))
        let (model, _) = try makeModel(connector, registry: registry)

        let sent = try sendTwice(model)
        for (_, task) in sent { await task.value }

        for (id, _) in sent {
            let question = model.conversations.first { $0.id == id }?.messages.last
            XCTAssertEqual(question?.role, .user)
            XCTAssertEqual(question?.failure?.message, "The other machine did not answer.")
        }
        XCTAssertTrue(model.liveReplies.isEmpty)
        XCTAssertNil(model.lastError, "the refusal went to an alert as well as the questions")
    }
}
