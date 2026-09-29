import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension OpenAICompatibleProvider {
    public func stream(_ chatRequest: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(chatRequest, into: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// gglib's `GET /v1/proxy/status/stream`: a full snapshot first, then
    /// about once a second.
    public func proxyStatusStream() -> AsyncThrowingStream<ProxyStatus, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = makeRequest(path: "proxy/status/stream", method: "GET", body: nil)
                    for try await item in try await eventStream(request, over: session) {
                        guard case .event(let event) = item else { continue }
                        continuation.yield(try decode(ProxyStatus.self, from: Data(event.data.utf8)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ chatRequest: ChatRequest, into continuation: AsyncStream<ChatEvent>.Continuation) async {
        let body: Data
        do {
            body = try JSONEncoder().encode(ChatCompletionRequest(chatRequest))
        } catch {
            continuation.yield(.error(.decoding("could not encode the request: \(error)")))
            return
        }
        let request = makeRequest(path: "chat/completions", method: "POST", body: body)
        var reply = ReplyState()
        do {
            for try await item in try await eventStream(request, over: streamingSession) {
                // `[DONE]` stops the reading. The reply then ends as it does
                // when the stream ends without an error.
                guard case .event(let event) = item else { break }
                switch read(event, into: &reply) {
                case .yield(let events):
                    for passed in events { continuation.yield(passed) }
                case .skip:
                    continue
                case .end(let events, let failure):
                    for passed in events { continuation.yield(passed) }
                    continuation.yield(.error(failure))
                    return
                }
            }
            continuation.yield(reply.ending)
        } catch is CancellationError {
            log.log(.debug, "stream cancelled")
        } catch let error as ProviderError {
            continuation.yield(.error(error))
        } catch {
            log.log(.error, "stream failed: \(error.localizedDescription)")
            continuation.yield(.error(.transport(error.localizedDescription)))
        }
    }

    /// What one event of a chat stream means for the reply.
    func read(_ event: SSEEvent, into reply: inout ReplyState) -> EventOutcome {
        // An event whose data is empty is a keepalive. It is not logged, and
        // it is not a skipped chunk.
        if event.data.isEmpty { return .skip }
        let data = Data(event.data.utf8)
        let chunk: ChatCompletionChunk
        do throws(ProviderError) {
            chunk = try decode(ChatCompletionChunk.self, from: data)
        } catch {
            return unreadable(data, failing: error, into: &reply)
        }
        if let usage = chunk.usage { reply.usage = usage }
        // Progress comes first, and it is neither text nor reasoning.
        var events: [ChatEvent] = chunk.promptProgress.map { [.progress($0)] } ?? []
        for choice in chunk.choices ?? [] {
            if let reasoning = choice.delta?.reasoningContent, !reasoning.isEmpty {
                events.append(.reasoning(reasoning))
                reply.passedTextOrReasoning = true
            }
            if let text = choice.delta?.content, !text.isEmpty {
                events.append(.delta(text))
                reply.passedTextOrReasoning = true
            }
            if let reason = choice.finishReason { reply.finishReason = reason }
        }
        // A failure written into the stream ends the reply here. gglib sends
        // `[DONE]` after it, and ending here is what keeps that from counting
        // the reply as finished.
        if let failure = chunk.error {
            return .end(after: events, with: .stream(code: failure.code, message: failure.message))
        }
        return .yield(events)
    }

    /// A chunk that did not decode. One that JSONSerialization reads as an
    /// object with a top-level member named `error` ends the reply, so a
    /// `[DONE]` after it does not finish the reply. Any other is skipped. Its
    /// log line gives the UTF-8 length of its text and nothing it held, not
    /// even the decoder's description of the failure, which can quote the
    /// chunk.
    private func unreadable(_ data: Data, failing error: ProviderError, into reply: inout ReplyState) -> EventOutcome {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if object?["error"] != nil {
            return .end(after: [], with: .stream(code: nil, message: Self.unreadableError))
        }
        if reply.firstSkipped == nil { reply.firstSkipped = error }
        log.log(.debug, "skipped a chunk this app could not read, \(data.count) bytes")
        return .skip
    }

    /// The message of the error a reply ends with at a chunk this app cannot
    /// read that has a top-level `error` member.
    private static let unreadableError = "the server reported an error part-way through the reply"

    /// Opens the connection on `session`, maps a non-2xx reply to
    /// `ProviderError.server`, and hands back parsed SSE items as they arrive.
    ///
    /// An event the stream ends in the middle of is passed on only when
    /// `flushingAtEnd`. A run's reader passes `false`: an event cut off by a
    /// dropped connection can hold half its data under a whole `id`, and the
    /// cursor would move past the half it never read.
    ///
    /// With `requiringEventStream`, a 2xx whose `Content-Type` names anything
    /// but `text/event-stream` is `ProviderError.invalidResponse`: something
    /// other than the server answered.
    func eventStream(
        _ request: URLRequest, over session: URLSession, flushingAtEnd: Bool = true,
        requiringEventStream: Bool = false
    ) async throws -> AsyncThrowingStream<SSEItem, any Error> {
        log.log(.debug, "\(request.httpMethod ?? "GET") \(Redaction.describe(request.url!))")
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse(String(describing: type(of: response)))
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.serverError(status: http.statusCode, body: body)
        }
        if requiringEventStream, let type = http.value(forHTTPHeaderField: "Content-Type"),
            !type.lowercased().hasPrefix("text/event-stream")
        {
            throw ProviderError.invalidResponse("the answer was \(type), not an event stream")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                var line: [UInt8] = []
                do {
                    for try await byte in bytes {
                        line.append(byte)
                        if byte == UInt8(ascii: "\n") {
                            for item in parser.feed(line) { continuation.yield(item) }
                            line.removeAll(keepingCapacity: true)
                        }
                    }
                    if flushingAtEnd {
                        for item in parser.feed(line) { continuation.yield(item) }
                        for item in parser.finish() { continuation.yield(item) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// What one event of a chat stream means for the reply.
enum EventOutcome {
    /// Pass these on, and read on.
    case yield([ChatEvent])
    /// Nothing to pass on; read on.
    case skip
    /// Pass these on, then end the reply with this error.
    case end(after: [ChatEvent], with: ProviderError)
}

/// What a reply has read so far, for the event that ends it.
struct ReplyState {
    var finishReason: String?
    var usage: Usage?
    /// Whether any text or reasoning has been passed on.
    var passedTextOrReasoning = false
    /// The decoding error of the first chunk that was skipped.
    var firstSkipped: ProviderError?

    /// How the reply ends when its stream ends without an error, at `[DONE]`
    /// or without it. A reply that skipped a chunk and passed on no text and
    /// no reasoning fails with the first skipped chunk's decoding error.
    var ending: ChatEvent {
        if !passedTextOrReasoning, let firstSkipped { return .error(firstSkipped) }
        return .finished(reason: finishReason, usage: usage)
    }
}
