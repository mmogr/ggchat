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
        model.addProvider(
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
}
