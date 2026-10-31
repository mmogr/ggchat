import SwiftData
import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// A conversation kept on this phone remembers how its picture was made:
/// the reply a run drew for keeps the call and the tool's answer, the
/// request after it carries them to gglib and to no other server, and what
/// the transcript shows is what it showed.
@MainActor
final class DrawnHistoryTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private static let png = Data("A PICTURE OF A FOX".utf8)
    private static let image = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 1024, height: 1024)
    private static let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
    private static let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private static func call(_ id: String) -> ToolExchange {
        ToolExchange(callID: id, name: "builtin:generate_image", arguments: #"{"prompt":"a red fox in snow"}"#)
    }

    private static func answered(_ id: String) -> ToolExchange {
        var call = call(id)
        call.result = drew
        call.images = [image.id]
        return call
    }

    /// The frames of a run that calls the tool under `id`, draws `image`
    /// and says a word, as gglib's agent events read.
    private static func frames(_ id: String) -> [[ChatEvent]] {
        [
            [.tool("Generate Image"), .toolCalled(call(id))],
            [.toolProgress(ToolProgress(callID: id, stage: .sampling, pass: 1, done: 4, total: 20))],
            [.toolEnded(id), .toolAnswered(callID: id, text: drew), .images([image], callID: id)],
            [.delta("A fox.")],
        ]
    }

    private func hub(_ id: String = "call_1") -> FakeRunHub {
        let hub = FakeRunHub(frames: Self.frames(id))
        hub.with { $0.images[Self.image.id] = Self.png }
        return hub
    }

    private func send(_ model: AppModel, _ text: String, draws: Bool = false, until count: Int) async throws {
        XCTAssertTrue(model.send(text, images: [], draws: draws))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == count }
    }

    /// The roles of the messages a request carries, as a server reads them.
    private func roles(_ request: ChatRequest) throws -> [String] {
        let body = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        let messages = try XCTUnwrap((body as? [String: Any])?["messages"] as? [[String: Any]])
        return messages.compactMap { $0["role"] as? String }
    }

    /// The reply a run drew for keeps the call and its answer with its
    /// words and its picture, in the store too, and the transcript holds
    /// the two messages it always did. The next message's request is marked
    /// for gglib and carries the call, the answer, the words, then itself.
    func testAReplyKeepsHowItsPictureWasMadeAndTheNextRequestCarriesIt() async throws {
        let store = InMemoryStore()
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, store: store)
        try await send(model, "a fox in snow", draws: true, until: 2)
        let reply = try Runs.last(model)
        XCTAssertEqual(reply.exchanges, [Self.answered("call_1")])
        XCTAssertEqual(reply.content, "A fox.")
        XCTAssertEqual(reply.images, [Self.image])
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(try store.loadConversations().first?.messages.last?.exchanges, [Self.answered("call_1")])

        hub.with { $0.frames = FakeRunHub.frames(ofText: "You are welcome.", reasoning: "") }
        try await send(model, "thanks", until: 4)
        let sent = try XCTUnwrap(hub.with { $0.starts.last?.request })
        XCTAssertTrue(sent.replaysToolCalls)
        XCTAssertFalse(sent.draws)
        XCTAssertEqual(sent.images, [:], "the picture's bytes were read for the model")
        XCTAssertEqual(try roles(sent), ["user", "assistant", "tool", "assistant", "user"])
        XCTAssertEqual(try Runs.last(model).exchanges, [], "a reply that called no tool kept one")
    }

    /// A gglib reached by its address reads the calls as a paired one does.
    /// A server not known to be gglib is sent the same conversation as its
    /// words alone, by the chat route.
    func testOnlyGglibIsSentTheCalls() async throws {
        let direct = hub()
        let (model, _) = try await Runs.makeModel(behind: direct, direct: true)
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages = [
            Message(role: .user, content: "a fox in snow", createdAt: Self.stamp, draws: true),
            Message(
                role: .assistant, content: "A fox.", createdAt: Self.stamp, images: [Self.image],
                exchanges: [Self.answered("call_1")]),
        ]
        model.update(conversation)
        try await send(model, "thanks", until: 4)
        let sent = try XCTUnwrap(direct.with { $0.starts.last?.request })
        XCTAssertTrue(sent.replaysToolCalls)
        XCTAssertEqual(try roles(sent).prefix(4), ["user", "assistant", "tool", "assistant"])

        let server = hub()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49997/v1"))
        model.registry.register(server, at: url)
        let other = ProviderConfig(name: "server", kind: .openAICompatible(baseURL: url), defaultModel: "m")
        try model.addProvider(other, credentials: [:])
        conversation = try XCTUnwrap(model.selectedConversation)
        conversation.providerID = other.id
        model.update(conversation)
        try await XCTUnwrap(model.send("and again")).value
        let plain = try XCTUnwrap(server.with { $0.chats.last })
        XCTAssertFalse(plain.replaysToolCalls, "a server not known to be gglib was sent tool messages")
        XCTAssertEqual(try roles(plain), ["user", "assistant", "user", "assistant", "user"])
        XCTAssertEqual(plain.messages[1].exchanges, [Self.answered("call_1")], "the calls left the conversation")
    }

    /// Two pictures in one conversation are two replies, each keeping the
    /// call its own run made under that run's id.
    func testTwoPicturesKeepTwoCallsUnderTheirOwnIDs() async throws {
        let hub = hub("call_1")
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub)
        try await send(model, "a fox in snow", draws: true, until: 2)
        hub.with { $0.frames = Self.frames("call_2") }
        try await send(model, "a bluer one", draws: true, until: 4)
        let replies = try XCTUnwrap(model.selectedConversation?.messages.filter { $0.role == .assistant })
        XCTAssertEqual(replies.map(\.exchanges), [[Self.answered("call_1")], [Self.answered("call_2")]])

        let second = try XCTUnwrap(hub.with { $0.starts.last?.request })
        XCTAssertTrue(second.draws)
        XCTAssertEqual(try roles(second), ["user", "assistant", "tool", "assistant", "user"])
    }

    /// A reply put down between the call and its answer keeps the call with
    /// no answer, and the reading that goes on from there puts the answer
    /// on it: the picture's bytes are lost on the way once, so the frame
    /// with the answer is first read by a second reading of the run.
    func testAnAnswerReadOnALaterReadingFindsItsCall() async throws {
        let hub = hub()
        hub.with { $0.fetchFailures = [.dropped(.transport("the connection dropped"))] }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub)
        try await send(model, "a fox in snow", draws: true, until: 2)
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 2])
        XCTAssertEqual(try Runs.last(model).exchanges, [Self.answered("call_1")])
        XCTAssertEqual(try Runs.last(model).content, "A fox.")
    }

    /// The calls outlive a reopening in one optional column, written only
    /// for a turn that has some, and a write that changes nothing marks no
    /// row. Bytes this build cannot read are no calls, and the turn's text
    /// still reads.
    func testTheCallsOutliveAReopening() throws {
        let container = SwiftDataStore.inMemoryContainer()
        let store = SwiftDataStore(container: container)
        var kept = Self.conversation()
        try store.save(conversation: kept)
        let read = try XCTUnwrap(try SwiftDataStore(container: container).loadConversations().first)
        XCTAssertEqual(read.messages.map(\.exchanges), [[], [Self.answered("call_1")]])
        XCTAssertEqual(read.messages, kept.messages)
        let rows = try store.context.fetch(FetchDescriptor<MessageRecord>()).sorted { $0.order < $1.order }
        XCTAssertEqual(rows.map { $0.exchangesData == nil }, [true, false])
        try store.write(read)
        XCTAssertFalse(store.context.hasChanges, "a write that changed nothing marked a row")

        kept.messages[1].exchanges.append(Self.call("call_2"))
        try store.save(conversation: kept)
        XCTAssertEqual(
            try store.loadConversations().first?.messages[1].exchanges, [Self.answered("call_1"), Self.call("call_2")])

        rows[1].exchangesData = Data("not json".utf8)
        try store.context.save()
        let unread = try XCTUnwrap(try store.loadConversations().first)
        XCTAssertEqual(unread.messages.map(\.exchanges), [[], []])
        XCTAssertEqual(unread.messages.map(\.content), ["a fox in snow", "A fox."])
    }

    private static func conversation() -> Conversation {
        Conversation(
            title: "a fox", providerID: UUID(), model: "m",
            messages: [
                Message(role: .user, content: "a fox in snow", createdAt: stamp, draws: true),
                Message(
                    role: .assistant, content: "A fox.", createdAt: stamp, images: [image],
                    exchanges: [answered("call_1")]),
            ], createdAt: stamp, updatedAt: stamp)
    }

    /// A store an earlier build wrote opens in this one, no reply holding a
    /// call. One this build wrote opens in this build with its calls, and
    /// under the earlier schema with its turns; the earlier build drops the
    /// column it does not know, so this build then opens that store with
    /// the turns and no calls.
    func testAStoreOpensAcrossTheCallsColumnInBothDirections() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
            let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let older = scratch.support.appending(path: "older.store")
        do {
            // Held: a context whose container has gone traps on its next use.
            let written = try container(BeforeDrawing.schema, at: older)
            let record = BeforeDrawing.ConversationRecord(id: UUID(), title: "before", createdAt: Self.stamp)
            written.mainContext.insert(record)
            let message = BeforeDrawing.MessageRecord(
                id: UUID(), role: "assistant", content: "A fox.", createdAt: Self.stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.messages.map(\.content), ["A fox."])
        XCTAssertEqual(read.messages.map(\.exchanges), [[]])

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: Self.conversation())
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            let kept = try XCTUnwrap(try store.loadConversations().first)
            XCTAssertEqual(kept.messages.map(\.exchanges), [[], [Self.answered("call_1")]])
        }
        do {
            let earlier = try container(BeforeDrawing.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeDrawing.MessageRecord>())
            XCTAssertEqual(rows.sorted { $0.order < $1.order }.map(\.content), ["a fox in snow", "A fox."])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.messages.map(\.content), ["a fox in snow", "A fox."])
        XCTAssertEqual(back.messages.map(\.exchanges), [[], []])
    }
}
