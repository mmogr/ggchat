import GGChatCore
import XCTest

@testable import GGChatUI

/// A system prompt is a setting of the conversation: it goes ahead of every
/// request the conversation makes, send, Continue and Retry alike, and is
/// never kept as one of its messages (ADR 0005).
final class AppModelSystemPromptTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:49996/v1")!
    private let prompt = "Answer in French."

    @MainActor
    private func makeModel(_ provider: any Provider) throws -> (AppModel, LoopbackProviderRegistry) {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: baseURL)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addProvider(
            ProviderConfig(name: "mock", kind: .openAICompatible(baseURL: baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        return (model, registry)
    }

    @MainActor
    func testTheSystemPromptIsSentAheadOfEveryRequestButNeverKept() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Bonjour.")]))
        let (model, _) = try makeModel(recorder)
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        model.setSystemPrompt("  \(prompt) \n", for: conversationID)
        XCTAssertEqual(model.selectedConversation?.systemPrompt, prompt, "the prompt is kept trimmed")

        let first = try XCTUnwrap(model.send("hi"))
        await first.value
        let second = try XCTUnwrap(model.send("again"))
        await second.value

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].messages.map(\.role), [.system, .user])
        XCTAssertEqual(requests[0].messages[0].content, prompt)
        XCTAssertEqual(requests[1].messages.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertEqual(requests[1].messages[0].content, prompt, "the prompt goes with every request, not the first")
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant], "the prompt was kept as a turn")
        XCTAssertEqual(messages[1].content, "Bonjour.")
    }

    /// Continue and Retry build their requests where send does, so both carry
    /// the prompt, and the prompt as it is now: an edit made while a reply
    /// sat half-finished reaches the Continue that resumes it.
    @MainActor
    func testContinueAndRetryResendTheSystemPrompt() async throws {
        let recorder = RecordingProvider(wrapping: HangingProvider())
        let (model, _) = try makeModel(recorder)
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        model.setSystemPrompt(prompt, for: conversationID)
        let hanging = try XCTUnwrap(model.send("go"))
        for _ in 0..<1_000 where model.liveReply?.content.isEmpty ?? true {
            await Task.yield()
        }
        XCTAssertEqual(model.liveReply?.content, "half ", "the reply never started, so this proves nothing")
        model.stop()
        await hanging.value
        XCTAssertEqual(model.selectedConversation?.messages.last?.isPartial, true)

        model.setSystemPrompt("Answer in German.", for: conversationID)
        recorder.wrap(MockProvider(scripts: [.init(text: "done")]))
        let resumed = try XCTUnwrap(model.continueReply())
        await resumed.value

        let refusal = ProviderError.server(status: 503, code: "upstream_timeout", message: "busy")
        recorder.wrap(MockProvider(scripts: [.init(text: "")], failure: refusal))
        let refused = try XCTUnwrap(model.send("and now?"))
        await refused.value
        XCTAssertNotNil(model.selectedConversation?.messages.last?.failure, "the question was not refused")
        recorder.wrap(MockProvider(scripts: [.init(text: "yes")]))
        let retried = try XCTUnwrap(model.retry())
        await retried.value

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[1].messages.map(\.role), [.system, .user, .assistant], "Continue")
        XCTAssertEqual(
            requests[1].messages[0].content, "Answer in German.", "Continue sent the prompt as it was, not as it is")
        XCTAssertEqual(requests[3].messages.map(\.role), [.system, .user, .assistant, .user], "Retry")
        XCTAssertEqual(requests[3].messages[0].content, "Answer in German.")
        XCTAssertEqual(requests[3].messages, requests[2].messages, "Retry asks exactly what was refused")
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(messages[1].content, "half done")
        XCTAssertFalse(messages.contains { $0.role == .system }, "the prompt was kept as a turn")
    }

    @MainActor
    func testClearingTheSystemPromptSendsNone() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "fine")]))
        let (model, _) = try makeModel(recorder)
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        model.setSystemPrompt(prompt, for: conversationID)
        let first = try XCTUnwrap(model.send("hi"))
        await first.value

        model.setSystemPrompt(" \n\t ", for: conversationID)
        XCTAssertNil(model.selectedConversation?.systemPrompt, "a blank prompt is kept as none")
        XCTAssertEqual(model.selectedConversation?.hasSystemPrompt, false)
        let second = try XCTUnwrap(model.send("again"))
        await second.value

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].messages.first?.role, .system)
        XCTAssertEqual(requests[1].messages.map(\.role), [.user, .assistant, .user], "a cleared prompt was still sent")
    }

    /// The prompt is written through the store and read back by the next
    /// launch, which sends it with its first request.
    @MainActor
    func testTheSystemPromptSurvivesARelaunch() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.makeContainer(inMemory: true, log: NoopLogSink()))
        let model = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink(), now: { .distantPast })
        try model.addProvider(
            ProviderConfig(name: "p", kind: .openAICompatible(baseURL: baseURL), defaultModel: "m"),
            credentials: [:])
        let conversation = model.newConversation()
        model.setSystemPrompt(prompt, for: conversation.id)

        let registry = LoopbackProviderRegistry()
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Bonjour.")]))
        registry.register(recorder, at: baseURL)
        let reloaded = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry)
        reloaded.load()
        XCTAssertEqual(reloaded.selectedConversationID, conversation.id)
        XCTAssertEqual(reloaded.selectedConversation?.systemPrompt, prompt)
        XCTAssertEqual(reloaded.selectedConversation?.messages, [], "the prompt was stored as a message")
        let task = try XCTUnwrap(reloaded.send("hi"))
        await task.value
        XCTAssertEqual(recorder.requests.first?.messages.map(\.role), [.system, .user])
        XCTAssertEqual(recorder.requests.first?.messages.first?.content, prompt)

        reloaded.setSystemPrompt("", for: conversation.id)
        let cleared = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry)
        cleared.load()
        XCTAssertNil(cleared.selectedConversation?.systemPrompt, "clearing the prompt left the old one in the store")
    }
}
