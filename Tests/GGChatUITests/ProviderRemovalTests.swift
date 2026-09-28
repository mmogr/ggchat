import GGChatCore
import XCTest

@testable import GGChatUI

/// Removing a provider while a reply is in flight: the reply through it is
/// put down the way Stop puts it down before its pipe is hung up, and a reply
/// through another provider goes on.
final class ProviderRemovalTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let serverURL = URL(string: "http://127.0.0.1:49996/v1")!

    /// A model holding one pipe, "home", connected, whose far machine answers
    /// every request with one token and then never finishes.
    @MainActor
    private func makeConnectedModel(registry: LoopbackProviderRegistry) async throws -> (AppModel, ProviderConfig) {
        let defaults = UserDefaults(suiteName: "ProviderRemovalTests.\(UUID().uuidString)")!
        let connector = MockPipeConnector(sleeper: ImmediateSleeper(), provider: HangingProvider(), registry: registry)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        await model.connectPipe(for: config)
        for _ in 0..<200 where model.pipeStatus(for: config.id) != .direct { await Task.yield() }
        XCTAssertEqual(model.pipeStatus(for: config.id), .direct, "the pipe never connected")
        return (model, config)
    }

    @MainActor
    private func waitForTheFirstToken(_ model: AppModel) async {
        for _ in 0..<200 where model.liveReply?.content.isEmpty != false { await Task.yield() }
        XCTAssertEqual(model.liveReply?.content, "half ", "the reply never started")
    }

    /// The reply is over, and its partial kept, by the time the pipe it came
    /// through is gone. `HangingProvider` never ends a reply by itself, and a
    /// hang-up does not end it either, so only the cancellation can.
    @MainActor
    func testRemovingAProviderCancelsTheReplyThroughItAndKeepsThePartial() async throws {
        let (model, config) = try await makeConnectedModel(registry: LoopbackProviderRegistry())
        model.newConversation()
        let streaming = try XCTUnwrap(model.send("go"))
        defer { streaming.cancel() }
        await waitForTheFirstToken(model)

        model.removeProvider(config.id)
        for _ in 0..<200 where model.pipeSession(for: config.id) != nil { await Task.yield() }
        XCTAssertNil(model.pipeSession(for: config.id), "the pipe was never hung up")

        XCTAssertFalse(model.isStreaming, "the reply outlived the pipe it came through")
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.role, .assistant, "what had arrived was thrown away")
        XCTAssertEqual(last.content, "half ")
        XCTAssertTrue(last.isPartial)
        XCTAssertNil(last.failure, "a removal is not a failure, as a stop is not")
        XCTAssertNil(model.lastError)
    }

    /// Only the reply through the provider being removed is put down.
    @MainActor
    func testRemovingAProviderLeavesAReplyThroughAnotherAlone() async throws {
        let registry = LoopbackProviderRegistry()
        let (model, home) = try await makeConnectedModel(registry: registry)
        registry.register(HangingProvider(), at: serverURL)
        let desk = ProviderConfig(name: "desk", kind: .openAICompatible(baseURL: serverURL), defaultModel: "mock-27b")
        try model.addProvider(desk, credentials: [:])
        var conversation = model.newConversation()
        conversation.providerID = desk.id
        model.update(conversation)
        let streaming = try XCTUnwrap(model.send("go"))
        defer { streaming.cancel() }
        await waitForTheFirstToken(model)

        model.removeProvider(home.id)
        for _ in 0..<200 where model.pipeSession(for: home.id) != nil { await Task.yield() }
        XCTAssertNil(model.pipeSession(for: home.id), "the removed pipe was never hung up")

        XCTAssertTrue(model.isStreaming, "a reply through another provider was put down")
        XCTAssertEqual(model.liveReply?.content, "half ")
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user])
        model.stop()
        await streaming.value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "half ")
    }
}
