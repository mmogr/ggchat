import GGChatCore
import XCTest

@testable import GGChatUI

/// Deleting a conversation whose send waits for its pipe ends the wait, as
/// Stop would: the conversation's Stop goes with it.
final class PipeWaitDeletionTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let serverURL = URL(string: "http://127.0.0.1:49995/v1")!

    /// The wait ends, and a send in another conversation, to a server that
    /// answers, is not refused as if a reply were still in flight.
    @MainActor
    func testDeletingAConversationEndsItsWait() async throws {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "PipeWaitDeletionTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: HeldSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let home = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(home, credentials: [.ticket: ticket, .token: "secret-token"])
        registry.register(MockProvider(), at: serverURL)
        let desk = ProviderConfig(name: "desk", kind: .openAICompatible(baseURL: serverURL), defaultModel: "mock-27b")
        try model.addProvider(desk, credentials: [:])

        await model.connectPipe(for: home)
        XCTAssertEqual(model.pipeStatus(for: home.id), .idle, "the pipe should still be looking")
        let waiting = model.newConversation()
        let send = try XCTUnwrap(model.send("anyone?"))
        for _ in 0..<200 where model.liveReply?.waitingFor == nil { await Task.yield() }
        XCTAssertEqual(model.liveReply?.waitingFor, home.id, "the send never waited")

        model.deleteConversation(waiting.id)
        for _ in 0..<200 where model.isStreaming { await Task.yield() }
        XCTAssertFalse(model.isStreaming, "the wait outlived its conversation")
        send.cancel()
        await send.value
        XCTAssertFalse(model.conversations.contains { $0.id == waiting.id }, "the ended wait wrote it back")

        var other = model.newConversation()
        other.providerID = desk.id
        model.update(other)
        let asked = try XCTUnwrap(model.send("a question to another machine"), "the send was refused")
        await asked.value
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user, .assistant])
        XCTAssertNil(model.lastError)
    }
}
