import GGChatCore
import XCTest

@testable import GGChatUI

/// A request refused before its first token keeps its sentence on the
/// question, where the transcript can draw it and a relaunch cannot lose it,
/// and Retry asks the same question again.
final class AppModelRefusalTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:49998/v1")!
    private let forgotten = ProviderError.server(
        status: 401, code: "invalid_api_key", message: "invalid or missing bearer token")

    @MainActor
    private func makeModel(_ provider: any Provider) throws -> (AppModel, LoopbackProviderRegistry) {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: baseURL)
        let suite = "AppModelRefusalTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addProvider(
            ProviderConfig(name: "Desk", kind: .openAICompatible(baseURL: baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        return (model, registry)
    }

    /// Every request refused before a token, with this error.
    private func refusing(_ error: ProviderError) -> MockProvider {
        MockProvider(scripts: [.init(text: "")], failure: error)
    }

    @MainActor
    func testARefusalBeforeTheFirstTokenIsKeptOnTheQuestion() async throws {
        let (model, _) = try makeModel(MockProvider(scripts: [.init(text: "a b c")], failAfterTokens: 0))
        let task = try XCTUnwrap(model.send("anyone?"))
        await task.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user], "nothing arrived, so no reply is made up")
        let failure = try XCTUnwrap(messages[0].failure, "the refusal went nowhere the transcript can draw")
        XCTAssertEqual(failure.message, "Could not reach the server: the mock connection dropped")
        XCTAssertEqual(failure.whereToLook, .connectingSide)
        XCTAssertEqual(failure.hint, WhereToLook.connectingSide.hint)
        XCTAssertEqual(
            model.streamError(for: try XCTUnwrap(model.selectedConversationID))?.whereToLook, .connectingSide)
    }

    @MainActor
    func testRetryAsksAgainAndClearsTheRefusal() async throws {
        let (model, registry) = try makeModel(refusing(forgotten))
        let refused = try XCTUnwrap(model.send("anyone?"))
        await refused.value
        let failure = try XCTUnwrap(model.selectedConversation?.messages.first?.failure)
        XCTAssertEqual(failure.message, "invalid or missing bearer token", "the server's sentence, verbatim")
        XCTAssertEqual(failure.code, "invalid_api_key")

        registry.register(MockProvider(scripts: [.init(text: "yes, here")]), at: baseURL)
        let retried = try XCTUnwrap(model.retry())
        await retried.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant], "Retry adds no second copy of the question")
        XCTAssertEqual(messages[0].content, "anyone?")
        XCTAssertNil(messages[0].failure)
        XCTAssertEqual(messages[1].content, "yes, here")
        XCTAssertFalse(messages[1].isPartial)
        XCTAssertNil(model.streamError(for: try XCTUnwrap(model.selectedConversationID)))
        XCTAssertEqual(model.diagnostics.continuePresses, 0, "Retry is not counted with Continue")
    }

    @MainActor
    func testRetryDoesNothingOnceTheQuestionIsAnswered() async throws {
        let (model, _) = try makeModel(MockProvider(scripts: [.init(text: "fine")]))
        XCTAssertNil(model.retry(), "an empty conversation has nothing to ask again")
        let task = try XCTUnwrap(model.send("hi"))
        await task.value
        XCTAssertNil(model.retry(), "an answered question has nothing to ask again")
        XCTAssertEqual(model.selectedConversation?.messages.count, 2)
    }

    @MainActor
    func testRetryWhileAReplyIsStreamingDoesNothing() async throws {
        let (model, registry) = try makeModel(refusing(forgotten))
        let refused = try XCTUnwrap(model.send("anyone?"))
        await refused.value
        let refusedID = try XCTUnwrap(model.selectedConversationID)

        registry.register(HangingProvider(), at: baseURL)
        model.newConversation()
        let hanging = try XCTUnwrap(model.send("still there?"))
        model.selectedConversationID = refusedID
        XCTAssertTrue(model.isStreaming)
        XCTAssertNil(model.retry(), "a second stream would orphan the one in flight")
        XCTAssertNotNil(model.selectedConversation?.messages.last?.failure, "the refusal was cleared for nothing")

        model.stop()
        await hanging.value
    }

    @MainActor
    func testARefusalOnAnEarlierQuestionIsNotRetried() async throws {
        let (model, registry) = try makeModel(refusing(forgotten))
        let refused = try XCTUnwrap(model.send("anyone?"))
        await refused.value
        registry.register(MockProvider(scripts: [.init(text: "yes")]), at: baseURL)
        let asked = try XCTUnwrap(model.send("hello?"))
        await asked.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .user, .assistant])
        XCTAssertNotNil(messages[0].failure, "what happened to the first question is still true of it")
        XCTAssertNil(model.retry(), "only the last turn can be asked again")
    }

    @MainActor
    func testARetryThatCannotStartKeepsTheRefusal() async throws {
        let (model, _) = try makeModel(refusing(forgotten))
        let refused = try XCTUnwrap(model.send("anyone?"))
        await refused.value
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.model = nil
        model.update(conversation)
        var provider = model.providers[0]
        provider.defaultModel = nil
        model.updateProvider(provider)

        XCTAssertNil(model.retry())
        XCTAssertEqual(model.lastError, "Pick a model first.")
        XCTAssertNotNil(
            model.selectedConversation?.messages.last?.failure, "the sentence went before anything was sent")
    }

    /// A stop is not a refusal, even when the provider reported the
    /// cancellation as a transport error before the stream ended: a
    /// cancelled request can, and whether that error arrives first is a race.
    @MainActor
    func testAStopBeforeTheFirstTokenWritesNoFailureEvenIfAnErrorRaced() async throws {
        let (model, _) = try makeModel(ErrorThenHangProvider())
        let task = try XCTUnwrap(model.send("go"))
        for _ in 0..<1_000 where model.liveReply?.error == nil {
            await Task.yield()
        }
        XCTAssertNotNil(model.liveReply?.error, "the error never arrived, so this proves nothing")
        model.stop()
        await task.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertNil(messages[0].failure, "a stop was kept as a refusal")
        XCTAssertNil(model.streamError(for: try XCTUnwrap(model.selectedConversationID)))
    }

    /// A question left with no reply by a stop has nothing wrong with it and
    /// nothing to continue, and Retry asks it again all the same, so going
    /// back to it is not retyping it.
    @MainActor
    func testAQuestionLeftWithNoReplyCanBeAskedAgain() async throws {
        let slow = MockProvider(
            scripts: [.init(text: "a b c")], sleeper: ContinuousClockSleeper(), tokenDelay: .seconds(30))
        let (model, registry) = try makeModel(slow)
        let stopped = try XCTUnwrap(model.send("go"))
        model.stop()
        await stopped.value
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user])
        XCTAssertNil(model.selectedConversation?.messages.last?.failure, "a stop is not a refusal")

        registry.register(MockProvider(scripts: [.init(text: "here")]), at: baseURL)
        let asked = try XCTUnwrap(model.retry(), "an unanswered question can be asked again")
        await asked.value
        XCTAssertEqual(model.selectedConversation?.messages.map(\.role), [.user, .assistant])
    }

    /// Going to the background cancels the reply as a stop does, so the same
    /// holds: the question is left alone, with no failure on it.
    @MainActor
    func testABackgroundBeforeTheFirstTokenWritesNoFailure() async throws {
        let (model, _) = try makeModel(ErrorThenHangProvider())
        _ = try XCTUnwrap(model.send("go"))
        for _ in 0..<1_000 where model.liveReply?.error == nil {
            await Task.yield()
        }
        XCTAssertNotNil(model.liveReply?.error, "the error never arrived, so this proves nothing")
        await model.scene(.background).value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertNil(messages[0].failure, "a background was kept as a refusal")
    }

    /// Reasoning is something arriving, so a failure after it has a reply to
    /// sit under: an empty partial, with its sentence and Continue, and not a
    /// refusal on the question.
    @MainActor
    func testAFailureAfterReasoningButNoContentLeavesAnEmptyPartial() async throws {
        let script = MockProvider.Script(reasoning: "thinking it over", text: "a b")
        let (model, _) = try makeModel(MockProvider(scripts: [script], failAfterTokens: 0))
        let task = try XCTUnwrap(model.send("go"))
        await task.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages[1].content, "")
        XCTAssertEqual(messages[1].reasoning, "thinking it over")
        XCTAssertTrue(messages[1].isPartial)
        XCTAssertEqual(messages[1].failure?.whereToLook, .connectingSide)
        XCTAssertNil(messages[0].failure, "the sentence goes under the reply, not the question")
        XCTAssertNil(model.retry(), "a partial reply is continued, not asked again")
        let resumed = try XCTUnwrap(model.continueReply())
        await resumed.value
    }

    @MainActor
    func testTheAdviceUnderARefusalFollowsTheKindOfProvider() throws {
        let (model, _) = try makeModel(MockProvider())
        let server = try XCTUnwrap(model.selectedConversation)
        let pipe = ProviderConfig(name: "Home", kind: .pipe(ticketDigest: "abc"))
        try model.addProvider(pipe, credentials: [:])
        var piped = model.newConversation()
        piped.providerID = pipe.id
        model.update(piped)
        let refused = Failure(forgotten)

        let pairAgain = try XCTUnwrap(model.advice(for: refused, in: piped))
        XCTAssertTrue(pairAgain.contains("gglib remote invite"), pairAgain)
        XCTAssertTrue(pairAgain.contains("Providers › Home › Pairing string"), pairAgain)
        let checkTheKey = try XCTUnwrap(model.advice(for: refused, in: server))
        XCTAssertTrue(checkTheKey.contains("Providers › Desk"), checkTheKey)
        XCTAssertFalse(checkTheKey.contains("gglib"), "a server's user is never told to run a gglib command")

        let busy = Failure(.server(status: 503, code: "upstream_timeout", message: "busy"))
        XCTAssertNil(model.advice(for: busy, in: piped), "a code with nothing to add adds nothing")
        XCTAssertNil(model.advice(for: Failure(.transport("gone")), in: server))
    }
}

/// Reports the request as cancelled and then hangs, the way a cancelled
/// request's transport error can arrive just before the cancellation itself
/// ends the stream.
private struct ErrorThenHangProvider: Provider {
    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.error(.transport("cancelled")))
        }
    }
}
