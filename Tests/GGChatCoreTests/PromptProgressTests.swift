import XCTest

@testable import GGChatCore

/// Refuses every request, so a test can tell which of a provider's two
/// sessions a request went over.
private final class RefusingURLProtocol: URLProtocol, @unchecked Sendable {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}

/// A long prompt is read before the first word: gglib says how far it has
/// got when asked, and the stream waits for it.
final class PromptProgressTests: XCTestCase {
    private let question = [Message(role: .user, content: "hi", createdAt: .distantPast)]

    private func collect(_ provider: OpenAICompatibleProvider) async -> [ChatEvent] {
        var events: [ChatEvent] = []
        for await event in provider.stream(ChatRequest(model: "Qwen3.8-27B", messages: question)) {
            events.append(event)
        }
        return events
    }

    private func stub(_ body: Data, host: String) {
        StubURLProtocol.register(
            host: host, path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [body]))
    }

    private func progress(_ events: [ChatEvent]) -> [PromptProgress] {
        events.compactMap { if case .progress(let progress) = $0 { progress } else { nil } }
    }

    private func encoded(_ request: ChatRequest) throws -> (text: String, object: [String: Any]) {
        let data = try JSONEncoder().encode(ChatCompletionRequest(request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (String(decoding: data, as: UTF8.self), object)
    }

    func testTheRequestAsksForProgressWhenToldAndHasNoSuchKeyOtherwise() throws {
        let asked = try encoded(ChatRequest(model: "m", messages: question, returnProgress: true))
        XCTAssertTrue(asked.text.contains(#""return_progress":true"#), asked.text)
        let unasked = try encoded(ChatRequest(model: "m", messages: question))
        XCTAssertNil(unasked.object["return_progress"], unasked.text)
        XCTAssertFalse(unasked.text.contains("return_progress"), unasked.text)
    }

    func testTheFixturesProgressFramesDecodeAsGGLibSentThem() throws {
        var parser = SSEParser()
        let items = parser.feed(try Fixtures.data("gglib-stream-reasoning.sse")) + parser.finish()
        let frames = try items.compactMap { item -> PromptProgress? in
            guard case .event(let event) = item, event.data != "[DONE]" else { return nil }
            return try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(event.data.utf8)).promptProgress
        }
        XCTAssertEqual(
            frames,
            [
                PromptProgress(processed: 42, total: 57, cache: 42, timeMs: 32),
                PromptProgress(processed: 53, total: 57, cache: 42, timeMs: 459),
                PromptProgress(processed: 57, total: 57, cache: 42, timeMs: 587),
            ])
    }

    func testTheProviderPassesProgressOnBeforeTheFirstReasoningAndStillFinishesOnce() async throws {
        stub(try Fixtures.data("gglib-stream-reasoning.sse"), host: "progress.test")
        let events = await collect(
            OpenAICompatibleProvider(
                baseURL: URL(string: "http://progress.test/v1")!, session: StubURLProtocol.makeSession()))
        XCTAssertEqual(progress(events).map(\.processed), [42, 53, 57])
        let lastProgress = try XCTUnwrap(events.lastIndex { if case .progress = $0 { true } else { false } })
        let firstReasoning = try XCTUnwrap(events.firstIndex { if case .reasoning = $0 { true } else { false } })
        XCTAssertEqual(lastProgress, 2, "the progress frames were not the first three events")
        XCTAssertLessThan(lastProgress, firstReasoning)
        XCTAssertEqual(events.filter { if case .finished = $0 { true } else { false } }.count, 1)
        guard case .finished? = events.last else { return XCTFail("the reply did not end finished: \(events)") }
    }

    /// A `prompt_progress` that does not read costs nothing else: the text
    /// beside it arrives, and on its own it is not a skipped chunk.
    func testAProgressMemberThatDoesNotReadIsDroppedAndTheRestOfTheChunkIsRead() async {
        let odd = #"{"prompt_progress":{"processed":"many"},"choices":[{"delta":{"content":"hi"},"index":0}]}"#
        stub(Data("data: \(odd)\n\ndata: [DONE]\n\n".utf8), host: "odd-progress.test")
        let events = await collect(
            OpenAICompatibleProvider(
                baseURL: URL(string: "http://odd-progress.test/v1")!, session: StubURLProtocol.makeSession()))
        XCTAssertEqual(events, [.delta("hi"), .finished(reason: nil, usage: nil)])
    }

    /// Built once, and waiting longer than gglib does: its own limit on
    /// silence is 300 seconds. Model lists and status requests keep the
    /// shared session.
    func testAProviderTheRegistryBuildsStreamsOnASessionThatWaitsTenMinutes() throws {
        let registry = LoopbackProviderRegistry()
        let url = try XCTUnwrap(URL(string: "http://192.0.2.1:8080/v1"))
        let provider = try XCTUnwrap(registry.makeProvider(baseURL: url, apiKey: nil) as? OpenAICompatibleProvider)
        XCTAssertEqual(provider.streamingSession.configuration.timeoutIntervalForRequest, 600)
        XCTAssertEqual(provider.streamingSession.configuration.timeoutIntervalForResource, 3600)
        XCTAssertTrue(provider.session === URLSession.shared, "a model list left the shared session")
        let another = try XCTUnwrap(
            LoopbackProviderRegistry().makeProvider(baseURL: url, apiKey: "k") as? OpenAICompatibleProvider)
        XCTAssertTrue(another.streamingSession === provider.streamingSession, "the session was built twice")
    }

    private func firstSnapshot(_ provider: OpenAICompatibleProvider) async throws -> ProxyStatus? {
        for try await snapshot in provider.proxyStatusStream() { return snapshot }
        return nil
    }

    /// A chat reply goes over the streaming session; a model list, a status
    /// request and the status stream go over the other.
    func testAChatStreamsOnTheStreamingSessionAndNothingElseDoes() async throws {
        let host = "two-sessions.test"
        let url = try XCTUnwrap(URL(string: "http://\(host)/v1"))
        stub(try Fixtures.data("gglib-stream-reasoning.sse"), host: host)
        let others = [
            "models": "gglib-models.json", "proxy/status": "gglib-proxy-status.json",
            "proxy/status/stream": "gglib-proxy-status-stream.sse",
        ]
        for (path, fixture) in others {
            StubURLProtocol.register(
                host: host, path: "/v1/\(path)", .init(status: 200, chunks: [try Fixtures.data(fixture)]))
        }
        let chatOnly = OpenAICompatibleProvider(
            baseURL: url, session: RefusingURLProtocol.makeSession(), streamingSession: StubURLProtocol.makeSession())
        guard case .finished? = await collect(chatOnly).last else { return XCTFail("the chat did not stream") }
        let models = try? await chatOnly.models()
        let status = try? await chatOnly.proxyStatus()
        let snapshot = try? await firstSnapshot(chatOnly)
        XCTAssertNil(models, "a model list went over the streaming session")
        XCTAssertNil(status, "a status request went over the streaming session")
        XCTAssertNil(snapshot, "the status stream went over the streaming session")

        let allButChat = OpenAICompatibleProvider(
            baseURL: url, session: StubURLProtocol.makeSession(), streamingSession: RefusingURLProtocol.makeSession())
        guard case .error(.transport)? = await collect(allButChat).last
        else { return XCTFail("the chat went over the other session") }
        let listed = try await allButChat.models()
        let answered = try await allButChat.proxyStatus()
        let streamed = try await firstSnapshot(allButChat)
        XCTAssertEqual(listed.count, 5)
        XCTAssertNotNil(answered)
        XCTAssertNotNil(streamed)
    }
}
