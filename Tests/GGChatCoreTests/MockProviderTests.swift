import XCTest

@testable import GGChatCore

final class MockProviderTests: XCTestCase {
    private func collect(_ provider: MockProvider) async -> [ChatEvent] {
        var events: [ChatEvent] = []
        let request = ChatRequest(
            model: "mock-27b", messages: [Message(role: .user, content: "hi", createdAt: .distantPast)])
        for await event in provider.stream(request) { events.append(event) }
        return events
    }

    func testTokensJoinBackToTheText() {
        let text = "one two\nthree  four"
        XCTAssertEqual(MockProvider.tokens(of: text).joined(), text)
        XCTAssertEqual(MockProvider.tokens(of: "a b"), ["a ", "b"])
    }

    func testScriptStreamsReasoningThenTextThenFinished() async {
        let script = MockProvider.Script(reasoning: "think first", text: "then answer")
        let events = await collect(MockProvider(scripts: [script]))
        let reasoning = events.compactMap { if case .reasoning(let text) = $0 { text } else { nil } }.joined()
        let text = events.compactMap { if case .delta(let text) = $0 { text } else { nil } }.joined()
        XCTAssertEqual(reasoning, "think first")
        XCTAssertEqual(text, "then answer")
        XCTAssertEqual(
            events.last,
            .finished(reason: "stop", usage: Usage(promptTokens: 1, completionTokens: 2, contextSize: 4_096)))
    }

    /// A finished reply counts a word as a token, read and written, and
    /// reports a context size beside the counts as gglib does, so a preview
    /// and a UI walk have a reading to draw. A mock told it has no size
    /// reports none, as a server that is not gglib, and a reply that fails
    /// reports nothing.
    func testTheMockReportsWhatItReadAndItsContext() async {
        func usage(_ provider: MockProvider) async -> Usage? {
            let request = ChatRequest(
                model: "mock-27b",
                messages: [
                    Message(role: .system, content: "Be brief.", createdAt: .distantPast),
                    Message(role: .user, content: "what is a ticket", createdAt: .distantPast),
                ])
            var last: ChatEvent?
            for await event in provider.stream(request) { last = event }
            guard case .finished("stop", let usage)? = last else { return nil }
            return usage
        }
        let script = MockProvider.Script(text: "a short answer")
        let counted = await usage(MockProvider(scripts: [script]))
        XCTAssertEqual(counted, Usage(promptTokens: 6, completionTokens: 3, contextSize: 4_096))
        XCTAssertEqual(ContextReading(counted, reason: "stop")?.used, 9)
        let sized = await usage(MockProvider(scripts: [script], contextSize: 100))
        XCTAssertEqual(sized?.contextSize, 100)
        let unsized = await usage(MockProvider(scripts: [script], contextSize: nil))
        XCTAssertEqual(unsized, Usage(promptTokens: 6, completionTokens: 3))
        XCTAssertNil(ContextReading(unsized, reason: "stop"))
        let failed = await usage(MockProvider(scripts: [script], failure: .transport("gone")))
        XCTAssertNil(failed)
    }

    /// The mock's first model thinks, as gglib would list it, and a request
    /// with a thinking budget of zero skips the script's reasoning and
    /// streams the same text, so a preview and a UI walk show the switch
    /// working. Any other budget, and none, thinks.
    func testABudgetOfZeroSkipsTheMocksReasoning() async {
        XCTAssertEqual(MockProvider.sampleModels.filter(\.thinks).map(\.id), ["mock-27b"])
        let provider = MockProvider(scripts: [.init(reasoning: "think first", text: "then answer")])
        func stream(budget: Int?) async -> [ChatEvent] {
            let request = ChatRequest(
                model: "mock-27b", messages: [Message(role: .user, content: "hi", createdAt: .distantPast)],
                reasoningBudgetTokens: budget)
            var events: [ChatEvent] = []
            for await event in provider.stream(request) { events.append(event) }
            return events
        }
        let finish = ChatEvent.finished(
            reason: "stop", usage: Usage(promptTokens: 1, completionTokens: 2, contextSize: 4_096))
        let answer: [ChatEvent] = [.delta("then "), .delta("answer"), finish]
        let off = await stream(budget: ChatRequest.noThinking)
        XCTAssertEqual(off, answer)
        for budget in [nil, -1, 1, 4_096] {
            let thought = await stream(budget: budget)
            XCTAssertEqual(thought, [.reasoning("think "), .reasoning("first")] + answer, "\(budget ?? -2)")
        }
    }

    func testFailAfterTokensEndsWithATransportError() async {
        let events = await collect(MockProvider(scripts: [.init(text: "a b c d e")], failAfterTokens: 3))
        let deltas = events.filter { if case .delta = $0 { true } else { false } }
        XCTAssertEqual(deltas.count, 3)
        XCTAssertEqual(events.last, .error(.transport("the mock connection dropped")))
    }

    /// On its own, a failure follows the whole script in place of the
    /// finish, the way a server ends a stream it wrote an error into; with an
    /// empty script it is a refusal before the first token.
    func testAFailureOnItsOwnEndsTheScriptInPlaceOfTheFinish() async {
        let refused = ProviderError.server(status: 401, code: "invalid_api_key", message: "no")
        let whole = await collect(MockProvider(scripts: [.init(text: "a b")], failure: refused))
        XCTAssertEqual(whole, [.delta("a "), .delta("b"), .error(refused)])
        let empty = await collect(MockProvider(scripts: [.init(text: "")], failure: refused))
        XCTAssertEqual(empty, [.error(refused)])
    }

    func testAFailureWithFailAfterTokensReplacesTheTransportError() async {
        let stopped = ProviderError.server(status: 500, code: "upstream_error", message: "gone")
        let events = await collect(MockProvider(scripts: [.init(text: "a b c")], failAfterTokens: 1, failure: stopped))
        XCTAssertEqual(events, [.delta("a "), .error(stopped)])
    }

    func testModelsAreListed() async throws {
        let models = try await MockProvider().models()
        XCTAssertEqual(models.map(\.id), ["mock-27b", "mock-4b"])
    }
}
