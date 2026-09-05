import XCTest

@testable import GGChatCore

final class OpenAICompatibleProviderTests: XCTestCase {
    private func provider(
        host: String, apiKey: String? = nil, log: any LogSink = NoopLogSink()
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, apiKey: apiKey,
            session: StubURLProtocol.makeSession(), log: log)
    }

    private func collect(_ provider: OpenAICompatibleProvider) async -> [ChatEvent] {
        var events: [ChatEvent] = []
        let request = ChatRequest(
            model: "Qwen3.8-27B", messages: [Message(role: .user, content: "hi", createdAt: .distantPast)])
        for await event in provider.stream(request) { events.append(event) }
        return events
    }

    func testStreamsRealGGLibCaptureSplitIntoPieces() async throws {
        let fixture = try Fixtures.data("gglib-stream-reasoning.sse")
        let pieces = stride(from: 0, to: fixture.count, by: 997).map { fixture[$0..<min($0 + 997, fixture.count)] }
        StubURLProtocol.register(
            host: "stream.test", path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: pieces))
        let events = await collect(provider(host: "stream.test"))
        let reasoning = events.compactMap { if case .reasoning(let text) = $0 { text } else { nil } }
        let text = events.compactMap { if case .delta(let text) = $0 { text } else { nil } }.joined()
        XCTAssertGreaterThan(reasoning.count, 5)
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(
            events.last,
            .finished(
                reason: "stop", usage: Usage(promptTokens: 57, completionTokens: 28, totalTokens: 85, cachedTokens: 42))
        )
        XCTAssertEqual(events.filter { if case .finished = $0 { true } else { false } }.count, 1)
    }

    func testUnauthorizedBecomesTheServersOwnSentence() async {
        StubURLProtocol.register(
            host: "auth.test", path: "/v1/chat/completions",
            .init(
                status: 401, chunks: [Data(#"{"error":{"message":"Invalid API key","code":"invalid_api_key"}}"#.utf8)]))
        let events = await collect(provider(host: "auth.test", apiKey: "wrong"))
        XCTAssertEqual(events, [.error(.server(status: 401, code: "invalid_api_key", message: "Invalid API key"))])
        guard case .error(let error)? = events.first else { return XCTFail("no error") }
        XCTAssertEqual(error.whereToLook, WhereToLook.servingSide)
    }

    func testModelsSendBearerOnlyWhenAKeyIsSet() async throws {
        let body = try Fixtures.data("gglib-models.json")
        StubURLProtocol.register(host: "models.test", path: "/v1/models", .init(status: 200, chunks: [body]))
        StubURLProtocol.register(host: "nokey.test", path: "/v1/models", .init(status: 200, chunks: [body]))
        let models = try await provider(host: "models.test", apiKey: "abc").models()
        XCTAssertEqual(models.count, 5)
        _ = try await provider(host: "nokey.test", apiKey: "").models()
        XCTAssertEqual(
            StubURLProtocol.requests(host: "models.test").last?.value(forHTTPHeaderField: "Authorization"), "Bearer abc"
        )
        XCTAssertNil(StubURLProtocol.requests(host: "nokey.test").last?.value(forHTTPHeaderField: "Authorization"))
    }

    func testProxyStatusIsNilOn404AndDecodesOn200() async throws {
        StubURLProtocol.register(
            host: "noproxy.test", path: "/v1/proxy/status", .init(status: 404, chunks: [Data("not found".utf8)]))
        StubURLProtocol.register(
            host: "proxy.test", path: "/v1/proxy/status",
            .init(status: 200, chunks: [try Fixtures.data("gglib-proxy-status.json")]))
        let none = try await provider(host: "noproxy.test").proxyStatus()
        XCTAssertNil(none)
        let status = try await provider(host: "proxy.test").proxyStatus()
        XCTAssertEqual(status?.slots.count, 1)
    }

    func testUnreachableHostIsATransportError() async {
        let events = await collect(provider(host: "nowhere.test"))
        guard case .error(.transport)? = events.last else { return XCTFail("\(events)") }
        XCTAssertEqual(events.count, 1)
    }

    func testNoCredentialEverReachesALogLine() async throws {
        let token = "ggchat-test-token-7f3a9c"
        let log = CapturingLogSink()
        let fixture = try Fixtures.data("gglib-stream-reasoning.sse")
        StubURLProtocol.register(
            host: "redact.test", path: "/v1/chat/completions", .init(status: 200, chunks: [fixture]))
        StubURLProtocol.register(
            host: "redact.test", path: "/v1/models",
            .init(status: 200, chunks: [try Fixtures.data("gglib-models.json")]))
        StubURLProtocol.register(
            host: "redact.test", path: "/v1/proxy/status", .init(status: 500, chunks: [Data("boom \(token)".utf8)]))
        let provider = provider(host: "redact.test", apiKey: token, log: log)
        _ = try await provider.models()
        _ = await collect(provider)
        _ = try? await provider.proxyStatus()
        _ = await collect(self.provider(host: "unreachable.test", apiKey: token, log: log))
        let sent = StubURLProtocol.requests(host: "redact.test").compactMap {
            $0.value(forHTTPHeaderField: "Authorization")
        }
        XCTAssertTrue(sent.allSatisfy { $0 == "Bearer \(token)" }, "the token was sent on every request")
        XCTAssertGreaterThan(log.lines.count, 2, "the provider does log, so an empty log would prove nothing")
        for line in log.lines {
            XCTAssertFalse(line.contains(token), "credential in log line: \(line)")
        }
    }
}
