import GGChatCore
import XCTest

@testable import GGChatUI

final class AppModelStreamingTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:49999/v1")!

    @MainActor
    private func makeModel(_ provider: MockProvider) -> (AppModel, LoopbackProviderRegistry) {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: baseURL)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        model.addProvider(
            ProviderConfig(name: "mock", kind: .openAICompatible(baseURL: baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        return (model, registry)
    }

    @MainActor
    func testSendStreamsAReplyIntoTheConversation() async throws {
        let script = MockProvider.Script(reasoning: "think", text: "Hello **there**.")
        let (model, _) = makeModel(MockProvider(scripts: [script]))
        let task = try XCTUnwrap(model.send("  hi  "))
        XCTAssertTrue(model.isStreaming)
        await task.value
        XCTAssertFalse(model.isStreaming)
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages[0].content, "hi")
        XCTAssertEqual(messages[1].content, "Hello **there**.")
        XCTAssertEqual(messages[1].reasoning, "think")
        XCTAssertFalse(messages[1].isPartial)
        XCTAssertNil(model.streamError(for: messages[0].id))
    }

    @MainActor
    func testStopBeforeTheFirstTokenLeavesOnlyTheQuestion() async throws {
        let slow = MockProvider(
            scripts: [.init(text: "a b c")], sleeper: ContinuousClockSleeper(), tokenDelay: .seconds(30))
        let (model, _) = makeModel(slow)
        let task = try XCTUnwrap(model.send("go"))
        model.stop()
        await task.value
        XCTAssertFalse(model.isStreaming)
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user], "nothing arrived, so nothing is kept")
        XCTAssertNil(model.streamError(for: try XCTUnwrap(model.selectedConversationID)))
    }

    @MainActor
    func testADroppedStreamKeepsThePartialAndContinueCarriesOn() async throws {
        let dropping = MockProvider(scripts: [.init(text: "one two three four")], failAfterTokens: 2)
        let (model, registry) = makeModel(dropping)
        let first = try XCTUnwrap(model.send("go"))
        await first.value
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        var last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertTrue(last.isPartial)
        XCTAssertEqual(last.content, "one two ")
        XCTAssertEqual(model.streamError(for: conversationID)?.whereToLook, .connectingSide)

        registry.register(MockProvider(scripts: [.init(text: "three four")]), at: baseURL)
        let second = try XCTUnwrap(model.continueReply())
        await second.value
        last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertFalse(last.isPartial)
        XCTAssertEqual(last.content, "one two three four")
        XCTAssertEqual(model.selectedConversation?.messages.count, 2, "Continue extends the partial message")
        XCTAssertNil(model.streamError(for: conversationID))
    }

    @MainActor
    func testModelsAreListedAndSelectionIsRemembered() async throws {
        let (model, _) = makeModel(MockProvider())
        let provider = try XCTUnwrap(model.providers.first)
        await model.refreshModels(for: provider)
        XCTAssertEqual(model.models(for: provider.id).map(\.id), ["mock-27b", "mock-4b"])
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        model.select(model: "mock-4b", for: conversationID)
        XCTAssertEqual(model.selectedConversation?.model, "mock-4b")
        XCTAssertEqual(model.providers.first?.defaultModel, "mock-4b")
    }

    @MainActor
    func testSendWithoutAModelRefusesWithASentence() {
        let (model, _) = makeModel(MockProvider())
        var provider = model.providers[0]
        provider.defaultModel = nil
        model.updateProvider(provider)
        var conversation = model.selectedConversation!
        conversation.model = nil
        model.update(conversation)
        XCTAssertNil(model.send("hi"))
        XCTAssertEqual(model.lastError, "Pick a model first.")
    }
}
