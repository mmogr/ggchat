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
        XCTAssertEqual(events.last, .finished(reason: "stop", usage: Usage(completionTokens: 2)))
    }

    func testFailAfterTokensEndsWithATransportError() async {
        let events = await collect(MockProvider(scripts: [.init(text: "a b c d e")], failAfterTokens: 3))
        let deltas = events.filter { if case .delta = $0 { true } else { false } }
        XCTAssertEqual(deltas.count, 3)
        XCTAssertEqual(events.last, .error(.transport("the mock connection dropped")))
    }

    func testModelsAreListed() async throws {
        let models = try await MockProvider().models()
        XCTAssertEqual(models.map(\.id), ["mock-27b", "mock-4b"])
    }
}
