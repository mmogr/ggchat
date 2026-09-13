import GGChatCore
import XCTest

@testable import GGChatUI

/// An error the server wrote into a stream that had already begun (#73): it
/// ends the reply there, partial, or goes on the question when nothing came
/// before it, and gglib's own notice of it is not kept as the reply.
final class AppModelStreamErrorTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:49997/v1")!

    @MainActor
    private func makeModel(_ provider: any Provider) throws -> (AppModel, LoopbackProviderRegistry) {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: baseURL)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addProvider(
            ProviderConfig(name: "Desk", kind: .openAICompatible(baseURL: baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        return (model, registry)
    }

    /// Every request ended before a token, with this error.
    private func refusing(_ error: ProviderError) -> MockProvider {
        MockProvider(scripts: [.init(text: "")], failure: error)
    }

    /// An error written into a stream after some of the reply ends it there,
    /// partial, with the error's code, and Continue carries on from it (#73).
    @MainActor
    func testAnErrorAfterSomeTextLeavesAPartialWithItsCode() async throws {
        let broke = ProviderError.stream(code: "upstream_error", message: "error decoding response body")
        let (model, registry) = try makeModel(
            MockProvider(scripts: [.init(text: "one two three")], failAfterTokens: 2, failure: broke))
        let task = try XCTUnwrap(model.send("go"))
        await task.value
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.role, .assistant)
        XCTAssertEqual(last.content, "one two ")
        XCTAssertTrue(last.isPartial, "a reply that broke was saved as finished")
        XCTAssertEqual(last.failure?.code, "upstream_error")
        XCTAssertEqual(last.failure?.whereToLook, .servingSide)
        XCTAssertEqual(model.streamError(for: try XCTUnwrap(model.selectedConversationID))?.code, "upstream_error")

        registry.register(MockProvider(scripts: [.init(text: "three")]), at: baseURL)
        let resumed = try XCTUnwrap(model.continueReply(), "a partial reply is continued")
        await resumed.value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "one two three")
    }

    /// With nothing before it, an error written into a stream is a refusal
    /// before the first token, and goes on the question.
    @MainActor
    func testAnErrorBeforeAnyTextLeavesTheRefusalOnTheQuestion() async throws {
        let waited = ProviderError.stream(code: "upstream_timeout", message: "upstream did not respond within 300s")
        let (model, _) = try makeModel(refusing(waited))
        let task = try XCTUnwrap(model.send("go"))
        await task.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertEqual(messages[0].failure?.code, "upstream_timeout")
        XCTAssertEqual(messages[0].failure?.whereToLook, .waitAndRetry)
    }

    /// gglib's own notice of the failure, which it writes as text before the
    /// error, is not kept as the reply: the error is drawn under the question
    /// instead. A notice whose interpolated upstream body runs over several
    /// lines is dropped all the same.
    @MainActor
    func testTheProxysNoticeIsNotKeptAsTheReply() async throws {
        let notice =
            "\u{26A0}\u{FE0F} [proxy] upstream model server error (502): upstream returned 502: <html>\n"
            + "<body>Bad Gateway</body>\n</html>"
        let broke = ProviderError.stream(code: "upstream_error", message: "upstream returned 502")
        let (model, _) = try makeModel(MockProvider(scripts: [.init(text: notice)], failure: broke))
        let task = try XCTUnwrap(model.send("go"))
        await task.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user], "the notice was kept as a reply")
        XCTAssertEqual(messages[0].failure?.code, "upstream_error")
    }

    /// The reasoning-only notice is followed by real output from the model,
    /// and must never be taken for a notice to drop: the space after
    /// `[proxy]` is what tells them apart.
    @MainActor
    func testTheReasoningOnlyNoticeIsNotANoticeToDrop() async throws {
        let promoted = "\n\n\u{26A0}\u{FE0F} [proxy: reasoning-only response] The answer is four."
        XCTAssertFalse(AppModel.isAProxyNotice(promoted))
        let broke = ProviderError.stream(code: "upstream_error", message: "gone")
        let (model, _) = try makeModel(MockProvider(scripts: [.init(text: promoted)], failure: broke))
        let task = try XCTUnwrap(model.send("go"))
        await task.value
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.content, promoted, "real output was dropped as a notice")
        XCTAssertTrue(last.isPartial)
    }

    /// A notice with no error after it, such as the one for a model that
    /// produced nothing, ended a stream that did finish: it is kept as the
    /// reply, because nothing else says what happened.
    @MainActor
    func testANoticeWithNoErrorIsKeptAsTheReply() async throws {
        let empty =
            "\u{26A0}\u{FE0F} [proxy] The model produced no output for this request. (finish_reason: stop)"
        let (model, _) = try makeModel(MockProvider(scripts: [.init(text: empty)]))
        let task = try XCTUnwrap(model.send("go"))
        await task.value
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.content, empty)
        XCTAssertFalse(last.isPartial)
    }
}
