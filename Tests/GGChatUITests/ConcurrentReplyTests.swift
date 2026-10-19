import GGChatCore
import XCTest

@testable import GGChatUI

/// A reply in flight is per conversation (ADR 0012): two conversations
/// stream at once, each reply ends in its own conversation, and what puts a
/// reply down — Stop, removing its provider, the background — reaches the
/// replies it should and no others.
final class ConcurrentReplyTests: XCTestCase {
    private let homeTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let officeTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2nb"
    private let serverURL = URL(string: "http://127.0.0.1:49993/v1")!

    /// A model with two pipes, "home" and "office", connected, and a server,
    /// "desk"; every one answers each request with one token and then never
    /// finishes.
    @MainActor
    private func makeModel(log: any LogSink = NoopLogSink()) async throws -> (AppModel, [ProviderConfig]) {
        let registry = LoopbackProviderRegistry()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ConcurrentReplyTests.\(UUID().uuidString)"))
        let connector = MockPipeConnector(sleeper: ImmediateSleeper(), provider: HangingProvider(), registry: registry)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: log, registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        var configs: [ProviderConfig] = []
        for (name, ticket) in [("home", homeTicket), ("office", officeTicket)] {
            let config = ProviderConfig(
                name: name, kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
            try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
            await model.connectPipe(for: config)
            for _ in 0..<200 where model.pipeStatus(for: config.id) != .direct { await Task.yield() }
            XCTAssertEqual(model.pipeStatus(for: config.id), .direct, "\(name) never connected")
            configs.append(config)
        }
        registry.register(HangingProvider(), at: serverURL)
        let desk = ProviderConfig(name: "desk", kind: .openAICompatible(baseURL: serverURL), defaultModel: "mock-27b")
        try model.addProvider(desk, credentials: [:])
        return (model, configs + [desk])
    }

    /// Opens a new conversation on `provider`, sends in it, and waits for
    /// the reply's first token.
    @MainActor
    private func ask(_ model: AppModel, through provider: ProviderConfig) async throws -> (UUID, Task<Void, Never>) {
        var conversation = model.newConversation()
        conversation.providerID = provider.id
        model.update(conversation)
        let task = try XCTUnwrap(model.send("go"), "the send through \(provider.name) was refused")
        for _ in 0..<200 where model.liveReplies[conversation.id]?.content.isEmpty != false { await Task.yield() }
        XCTAssertEqual(model.liveReplies[conversation.id]?.content, "half ", "the reply never started")
        return (conversation.id, task)
    }

    @MainActor
    private func messages(_ model: AppModel, _ id: UUID) -> [Message] {
        model.conversations.first { $0.id == id }?.messages ?? []
    }

    /// A send in a second conversation goes while the first streams, each
    /// reply is written into its own conversation, and Stop in one leaves
    /// the other streaming. A second send in a conversation still streaming
    /// is refused.
    @MainActor
    func testTwoConversationsStreamAtOnceAndEachKeepsItsOwnReply() async throws {
        let (model, providers) = try await makeModel()
        let (first, firstTask) = try await ask(model, through: providers[0])
        let (second, secondTask) = try await ask(model, through: providers[2])
        XCTAssertEqual(Set(model.liveReplies.keys), [first, second])

        model.selectedConversationID = first
        XCTAssertNil(model.send("again"), "a second reply in one conversation would orphan the first")

        model.stop(first)
        await firstTask.value
        XCTAssertEqual(messages(model, first).map(\.content), ["go", "half "])
        XCTAssertTrue(model.isStreaming(second), "Stop in one conversation put down the other's reply")
        XCTAssertEqual(messages(model, second).map(\.role), [.user])

        model.stop(second)
        await secondTask.value
        XCTAssertEqual(messages(model, second).map(\.content), ["go", "half "])
        XCTAssertTrue(model.liveReplies.isEmpty)
    }

    /// Removing a provider puts down every reply through it, keeping what
    /// arrived, and leaves the reply through another provider streaming.
    @MainActor
    func testRemovingAProviderStopsOnlyTheRepliesThroughIt() async throws {
        let (model, providers) = try await makeModel()
        let home = providers[0]
        let (one, oneTask) = try await ask(model, through: home)
        let (two, twoTask) = try await ask(model, through: home)
        let (other, otherTask) = try await ask(model, through: providers[2])

        model.removeProvider(home.id)
        await oneTask.value
        await twoTask.value
        for _ in 0..<200 where model.pipeSession(for: home.id) != nil { await Task.yield() }

        for id in [one, two] {
            XCTAssertFalse(model.isStreaming(id), "a reply outlived the provider it came through")
            XCTAssertEqual(messages(model, id).last?.content, "half ", "what had arrived was thrown away")
        }
        XCTAssertTrue(model.isStreaming(other), "a reply through another provider was put down")
        model.stop(other)
        await otherTask.value
    }

    /// The background puts down every reply in flight, keeping each one's
    /// partial in its own conversation, and logs each pipe a reply was
    /// streaming through as closed mid-reply.
    @MainActor
    func testTheBackgroundPutsDownEveryReply() async throws {
        let log = CapturingLogSink()
        let (model, providers) = try await makeModel(log: log)
        var asked: [(UUID, Task<Void, Never>)] = []
        for provider in providers { asked.append(try await ask(model, through: provider)) }

        await model.scene(.background).value
        for (_, task) in asked { await task.value }

        XCTAssertTrue(model.liveReplies.isEmpty, "a reply outlived the background")
        for (id, _) in asked {
            XCTAssertEqual(messages(model, id).map(\.content), ["go", "half "])
            XCTAssertEqual(messages(model, id).last?.isPartial, true)
        }
        let midReply = log.lines.filter { $0.contains("pipe closed mid-reply") }
        XCTAssertEqual(midReply.count, 2, "\(log.lines)")
    }
}
