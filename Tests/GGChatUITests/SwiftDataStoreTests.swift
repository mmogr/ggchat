import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

final class SwiftDataStoreTests: XCTestCase {
    @MainActor
    private func makeStore() -> SwiftDataStore {
        SwiftDataStore(container: SwiftDataStore.makeContainer(inMemory: true, log: NoopLogSink()))
    }

    @MainActor
    func testProvidersRoundTripInOrderAndDelete() throws {
        let store = makeStore()
        let first = ProviderConfig(name: "a", kind: .openAICompatible(baseURL: URL(string: "http://a/v1")!))
        let second = ProviderConfig(name: "b", kind: .pipe(ticketDigest: "abc"), defaultModel: "m")
        try store.save(provider: first)
        try store.save(provider: second)
        XCTAssertEqual(try store.loadProviders(), [first, second])
        var renamed = first
        renamed.name = "A"
        try store.save(provider: renamed)
        XCTAssertEqual(try store.loadProviders(), [renamed, second])
        try store.deleteProvider(id: first.id)
        XCTAssertEqual(try store.loadProviders(), [second])
    }

    @MainActor
    func testConversationsRoundTripWithMessagesInOrder() throws {
        let store = makeStore()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        var conversation = Conversation(title: "t", providerID: UUID(), model: "m", createdAt: stamp, updatedAt: stamp)
        conversation.messages = [
            Message(role: .user, content: "hi", createdAt: stamp),
            Message(role: .assistant, content: "hello", reasoning: "greet", isPartial: true, createdAt: stamp),
        ]
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation])

        conversation.messages[1].content = "hello there"
        conversation.messages[1].isPartial = false
        conversation.messages.removeFirst()
        conversation.messages.append(Message(role: .user, content: "again", createdAt: stamp))
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation])

        try store.deleteConversation(id: conversation.id)
        XCTAssertEqual(try store.loadConversations(), [])
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<MessageRecord>()).count, 0, "messages cascade")
    }

    @MainActor
    func testAppModelKeepsSelectionAndPersistsThroughTheStore() throws {
        let store = makeStore()
        let model = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink(), now: { .distantPast })
        try model.addProvider(
            ProviderConfig(name: "p", kind: .openAICompatible(baseURL: URL(string: "http://p/v1")!), defaultModel: "m"),
            credentials: [.apiKey: "k"])
        let conversation = model.newConversation()
        XCTAssertEqual(model.selectedConversationID, conversation.id)
        XCTAssertEqual(conversation.model, "m")
        let reloaded = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink())
        reloaded.load()
        XCTAssertEqual(reloaded.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(reloaded.providers.map(\.name), ["p"])
        XCTAssertEqual(
            reloaded.selectedConversationID, conversation.id,
            "reopening returns you to the most recent conversation")
    }

    /// The sentence under the turn that failed is written and read back by
    /// the store, on the question and on a partial reply alike, and clearing
    /// it clears it: the path that updates a row writes the field as well as
    /// the one that inserts it.
    @MainActor
    func testAFailureSurvivesTheRoundTrip() throws {
        let store = makeStore()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let refused = Failure(.server(status: 401, code: "invalid_api_key", message: "invalid or missing bearer token"))
        let dropped = Failure(.transport("the network went away"))
        var conversation = Conversation(title: "t", createdAt: stamp, updatedAt: stamp)
        conversation.messages = [
            Message(role: .user, content: "anyone?", failure: refused, createdAt: stamp),
            Message(role: .user, content: "go on", createdAt: stamp),
            Message(role: .assistant, content: "half", isPartial: true, failure: dropped, createdAt: stamp),
        ]
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation])

        conversation.messages[0].failure = nil
        conversation.messages[2].failure = refused
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation], "an existing row did not take the new value")
    }

    /// The prompt is written and read back with its conversation, on the row
    /// that is inserted and on the one that is updated, and clearing it
    /// clears it. It is never written as a message.
    @MainActor
    func testASystemPromptSurvivesTheRoundTrip() throws {
        let store = makeStore()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        var conversation = Conversation(
            title: "t", messages: [Message(role: .user, content: "hi", createdAt: stamp)],
            systemPrompt: "Answer in French.", createdAt: stamp, updatedAt: stamp)
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation])
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<MessageRecord>()).count, 1, "the prompt became a row")

        conversation.systemPrompt = "Answer in German."
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation], "an existing row did not take the new value")

        conversation.systemPrompt = nil
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation], "clearing the prompt left the old one behind")
    }

    /// With twenty providers stored, an edit to one lands on that one and
    /// deleting it takes only that one: every other provider reads back
    /// exactly as it was saved.
    @MainActor
    func testOneProviderAmongManyIsUpdatedAndDeletedByItsOwnKey() throws {
        let store = makeStore()
        var providers = (0..<20).map { index in
            ProviderConfig(name: "p\(index)", kind: .pipe(ticketDigest: "d\(index)"), defaultModel: "m\(index)")
        }
        for provider in providers {
            try store.save(provider: provider)
        }
        let byID = { (list: [ProviderConfig]) in Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) }) }
        func stored() throws -> [UUID: ProviderConfig] { byID(try store.loadProviders()) }
        XCTAssertEqual(try stored(), byID(providers))

        providers[7].name = "edited"
        providers[7].kind = .openAICompatible(baseURL: URL(string: "http://edited/v1")!)
        providers[7].defaultModel = nil
        try store.save(provider: providers[7])
        XCTAssertEqual(try stored(), byID(providers), "the edit landed somewhere other than its own row")

        let deleted = providers.remove(at: 7)
        try store.deleteProvider(id: deleted.id)
        XCTAssertEqual(try stored(), byID(providers), "the delete took a row other than its own")
    }

    /// With twenty conversations stored, an edit to one lands on that one
    /// and deleting it takes only that one and its messages: every other
    /// conversation reads back exactly as it was saved.
    @MainActor
    func testOneConversationAmongManyIsUpdatedAndDeletedByItsOwnKey() throws {
        let store = makeStore()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        var conversations = (0..<20).map { index in
            Conversation(
                title: "c\(index)", messages: [Message(role: .user, content: "m\(index)", createdAt: stamp)],
                createdAt: stamp, updatedAt: stamp)
        }
        for conversation in conversations {
            try store.save(conversation: conversation)
        }
        let byID = { (list: [Conversation]) in Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) }) }
        func stored() throws -> [UUID: Conversation] { byID(try store.loadConversations()) }
        XCTAssertEqual(try stored(), byID(conversations))

        conversations[7].title = "edited"
        conversations[7].messages.append(Message(role: .assistant, content: "reply", createdAt: stamp))
        try store.save(conversation: conversations[7])
        XCTAssertEqual(try stored(), byID(conversations), "the edit landed somewhere other than its own row")

        let deleted = conversations.remove(at: 7)
        try store.deleteConversation(id: deleted.id)
        XCTAssertEqual(try stored(), byID(conversations), "the delete took a row other than its own")
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<MessageRecord>()).count, 19, "messages cascade")
    }
}
