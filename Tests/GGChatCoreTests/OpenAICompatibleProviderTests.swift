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

    private func stream(_ body: String, host: String, log: any LogSink = NoopLogSink()) async -> [ChatEvent] {
        StubURLProtocol.register(
            host: host, path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [Data(body.utf8)]))
        return await collect(provider(host: host, log: log))
    }

    private func finishes(_ events: [ChatEvent]) -> Int {
        events.filter { if case .finished = $0 { true } else { false } }.count
    }

    /// gglib answers a stream that breaks part-way with `200`, the text so far,
    /// a bare `{"error":…}` event and `[DONE]`. The error ends the reply, and
    /// the `[DONE]` after it no longer counts it as finished (#73).
    func testAnErrorEventInsideAStreamEndsItWithTheErrorAndNoFinished() async throws {
        let fixture = try Fixtures.data("gglib-stream-upstream-error.sse")
        StubURLProtocol.register(
            host: "broken.test", path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [fixture]))
        let events = await collect(provider(host: "broken.test"))
        let text = events.compactMap { if case .delta(let text) = $0 { text } else { nil } }.joined()
        XCTAssertEqual(text, "The answer is", "the text before the error survives")
        XCTAssertEqual(
            events.last, .error(.stream(code: "upstream_error", message: "error decoding response body")))
        XCTAssertEqual(finishes(events), 0, "a reply that broke was counted as finished")
    }

    /// For three of its in-stream errors gglib first writes a visible notice as
    /// an ordinary chunk. The provider passes it on as text; keeping it out of
    /// the reply is the app's business, not the wire's.
    func testTheProxysVisibleNoticeArrivesAsAnOrdinaryDeltaBeforeTheError() async throws {
        let fixture = try Fixtures.data("gglib-stream-upstream-timeout.sse")
        StubURLProtocol.register(
            host: "timeout.test", path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [fixture]))
        let events = await collect(provider(host: "timeout.test"))
        guard case .delta(let notice)? = events.first else { return XCTFail("no notice first: \(events)") }
        XCTAssertTrue(notice.hasPrefix("\u{26A0}\u{FE0F} [proxy] "), notice)
        XCTAssertEqual(
            events.last, .error(.stream(code: "upstream_timeout", message: "upstream did not respond within 300s")))
        XCTAssertEqual(finishes(events), 0)
    }

    /// gglib's frame has no `choices` key, but this reads a wire it does not
    /// own: an `error` beside an empty `choices` still ends the reply.
    func testAnErrorFrameThatAlsoCarriesChoicesStillEndsTheStream() async {
        let events = await stream(
            #"data: {"choices":[{"delta":{"content":"half"},"index":0}]}"# + "\n\n"
                + #"data: {"choices":[],"error":{"message":"gone","code":"upstream_error"}}"# + "\n\n"
                + "data: [DONE]\n\n",
            host: "both.test")
        XCTAssertEqual(events, [.delta("half"), .error(.stream(code: "upstream_error", message: "gone"))])
    }

    /// llama.cpp has been seen to send `error` as a bare string. It is still
    /// an error, with no code, and not a decoding failure.
    func testAnErrorSentAsABareStringIsStillAnError() async {
        let events = await stream(
            #"data: {"error":"model crashed"}"# + "\n\ndata: [DONE]\n\n", host: "string.test")
        XCTAssertEqual(events, [.error(.stream(code: nil, message: "model crashed"))])
    }

    /// The one line the provider logs for a chat request of its own.
    private func requestLine(host: String) -> String {
        "[debug] POST http://\(host)/v1/chat/completions"
    }

    /// Why the provider's own decoder refuses `chunk`, or nil if it reads.
    private func decodingError(_ chunk: String) -> ProviderError? {
        do throws(ProviderError) {
            _ = try provider(host: "decode.test").decode(ChatCompletionChunk.self, from: Data(chunk.utf8))
            return nil
        } catch {
            return error
        }
    }

    /// Each chunk as a `data:` event, with `gap` before, between and after them.
    private func sse(_ chunks: [String], gap: String = "", done: Bool = true) -> String {
        gap + chunks.map { "data: \($0)\n\n" }.joined(separator: gap) + gap + (done ? "data: [DONE]\n\n" : "")
    }

    /// Three events whose data is empty: bare, under `event:` and under `id:`.
    private let keepalives = "data:\n\nevent: ping\ndata:\n\nid: 7\ndata:\n\n"
    private let usageChunk = #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#
    private let usage = Usage(promptTokens: 3, completionTokens: 2, totalTokens: 5)

    /// Unreadable chunks with no top-level `error` member are skipped, before
    /// any text and between two pieces of it, and the text and the reasoning
    /// after them arrive (#84). Six of them hold `error` or `Error`.
    func testAnUnreadableChunkWithNoErrorMemberIsSkippedAndTheTextAfterItArrives() async {
        let events = await stream(
            sse([
                #"{"choices":5}"#, #"{"choices":[{"delta":{"content":"one "},"index":0}]}"#, "not json at all",
                #"{"choices":5,"meta":{"error":1}}"#, #"{"choices":5,"Error":1}"#, #"{"choices":"error"}"#,
                "{error: 42}", #"{"choices":5,"errors":1}"#, #"[{"error":1}]"#,
                #"{"choices":[{"delta":{"content":"two"},"index":0,"finish_reason":"stop"}]}"#, usageChunk,
            ]) + sse([#"{"choices":[{"delta":{"content":"late"},"index":0}]}"#], done: false), host: "skip.test")
        XCTAssertEqual(events, [.delta("one "), .delta("two"), .finished(reason: "stop", usage: usage)])
        let thought = #"{"choices":[{"delta":{"reasoning_content":"hm"},"index":0}]}"#
        let reasoning = await stream(sse([#"{"choices":5}"#, thought]), host: "skip-reasoning.test")
        XCTAssertEqual(reasoning, [.reasoning("hm"), .finished(reason: nil, usage: nil)])
    }

    /// Keepalives before the first chunk, between chunks, after the chunk
    /// with the finish reason and after the usage chunk end nothing, are not
    /// logged, and leave the reply as it is without them. Keepalives and then
    /// `[DONE]` end as `[DONE]` alone does.
    func testAnEmptyDataLineIsAKeepaliveNotAFailure() async {
        let chunks = [
            #"{"choices":[{"delta":{"content":"one "},"index":0}]}"#,
            #"{"choices":[{"delta":{"content":"two"},"index":0,"finish_reason":"stop"}]}"#, usageChunk,
        ]
        let log = CapturingLogSink()
        let events = await stream(sse(chunks, gap: keepalives), host: "keepalive.test", log: log)
        XCTAssertEqual(events, [.delta("one "), .delta("two"), .finished(reason: "stop", usage: usage)])
        let without = await stream(sse(chunks), host: "no-keepalive.test")
        XCTAssertEqual(events, without, "keepalives changed how the reply ends")
        XCTAssertEqual(log.lines, [requestLine(host: "keepalive.test")], "a keepalive was logged")
        let bare = await stream("data: [DONE]\n\n", host: "bare-done.test")
        XCTAssertEqual(bare, [.finished(reason: nil, usage: nil)], "a bare [DONE] no longer finishes an empty reply")
        let only = await stream(keepalives + "data: [DONE]\n\n", host: "keepalives-only.test")
        XCTAssertEqual(only, bare, "a keepalive counted as a skipped chunk")
    }

    /// A chunk this app cannot read, with a top-level member named `error`,
    /// ends the reply, and the `[DONE]` after it does not finish it: after
    /// text, with a `choices` beside the member, and not logged as skipped;
    /// and after a chunk that was skipped, with no other member.
    func testAnUnreadableChunkThatCarriesAnErrorStillEndsTheReply() async {
        let log = CapturingLogSink()
        let half = #"{"choices":[{"delta":{"content":"half"},"index":0}]}"#
        let events = await stream(sse([half, #"{"choices":5,"error":42}"#]), host: "unreadable-error.test", log: log)
        let unread = ProviderError.stream(code: nil, message: "the server reported an error part-way through the reply")
        XCTAssertEqual(events, [.delta("half"), .error(unread)])
        XCTAssertEqual(log.lines, [requestLine(host: "unreadable-error.test")], "an error was logged as skipped")
        let afterASkip = await stream(sse(["not json at all", #"{"error":42}"#]), host: "skip-then-error.test")
        XCTAssertEqual(afterASkip, [.error(unread)])
    }

    /// A reply that skipped a chunk and got no text and no reasoning fails with the first skipped
    /// chunk's decoding error: with a progress frame, a usage and a finish reason read, the finish
    /// reason's chunk holding empty text and empty reasoning; without `[DONE]`; with keepalives.
    /// When the one chunk skipped is not JSON, it fails too.
    func testAReplyThatSkippedAChunkAndGotNoTextOrReasoningFails() async {
        let first = #"{"choices":5}"#
        let second = "not json at all"
        guard case .decoding(let firstWhy)? = decodingError(first),
            case .decoding(let secondWhy)? = decodingError(second)
        else { return XCTFail("a chunk here decoded") }
        XCTAssertNotEqual(firstWhy, secondWhy, "the two fail alike, so which one ends the reply proves nothing")
        let events = await stream(sse([first, second]), host: "unreadable.test")
        XCTAssertEqual(events, [.error(.decoding(firstWhy))])
        let stop = #"{"choices":[{"delta":{"content":"","reasoning_content":""},"index":0,"finish_reason":"stop"}]}"#
        let progress = #"{"object":"chat.completion.chunk","prompt_progress":{"processed":1,"total":1}}"#
        let read = await stream(sse([progress, first, stop, second, usageChunk]), host: "unreadable-read.test")
        XCTAssertEqual(read, [.progress(.init(processed: 1, total: 1))] + events, "a progress frame counted as text")
        let closed = await stream(sse([first, stop, second, usageChunk], done: false), host: "unreadable-closed.test")
        XCTAssertEqual(closed, events, "a stream that ended without [DONE] ended another way")
        let kept = await stream(sse([first, stop, second, usageChunk], gap: keepalives), host: "unreadable-kept.test")
        XCTAssertEqual(kept, events, "a keepalive changed how a reply with no text ends")
        let notJSON = await stream(sse([second]), host: "unreadable-not-json.test")
        guard notJSON.count == 1, case .error(.decoding)? = notJSON.first
        else { return XCTFail("a skipped chunk that is not JSON was not counted: \(notJSON)") }
    }

    /// The log of a stream that skips two chunks is the request's line and a
    /// size line for each. No line holds the sentinel in the first chunk or
    /// the number in the second, which the decoder's description quotes.
    func testASkippedChunksBytesNeverReachALogLine() async {
        let text = "ggchat-skipped-chunk-5d21e8"
        let number = "73519826401739284017392840173928"
        let quoted = #"{"choices":[{"delta":{"content":"caf\#u{E9} \#(text)"},"index":0}],"usage":5}"#
        let overflow = #"{"usage":{"prompt_tokens":\#(number)}}"#
        XCTAssertNotEqual(quoted.utf8.count, quoted.count, "this chunk's size is the same in bytes and characters")
        XCTAssertThrowsError(try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(overflow.utf8))) {
            XCTAssertTrue(String(describing: $0).contains(number), "the decoder no longer quotes this chunk")
        }
        let log = CapturingLogSink()
        let events = await stream(
            #"data: {"choices":[{"delta":{"content":"kept"},"index":0}]}"# + "\n\n"
                + "data: \(quoted)\n\ndata:\n\ndata: \(overflow)\n\ndata: [DONE]\n\n",
            host: "sentinel.test", log: log)
        XCTAssertEqual(events, [.delta("kept"), .finished(reason: nil, usage: nil)])
        let sizes = [quoted, overflow].map { "[debug] skipped a chunk this app could not read, \($0.utf8.count) bytes" }
        XCTAssertEqual(log.lines, [requestLine(host: "sentinel.test")] + sizes)
        for line in log.lines {
            XCTAssertFalse(line.contains(text) || line.contains(number), "a skipped chunk in a log line: \(line)")
        }
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
