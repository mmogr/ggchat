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
                    for try await item in try await eventStream(request) {
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
        var finishReason: String?
        var usage: Usage?
        var finished = false
        do {
            for try await item in try await eventStream(request) {
                switch item {
                case .done:
                    finished = true
                    continuation.yield(.finished(reason: finishReason, usage: usage))
                    return
                case .event(let event):
                    let chunk = try decode(ChatCompletionChunk.self, from: Data(event.data.utf8))
                    if let chunkUsage = chunk.usage { usage = chunkUsage }
                    for choice in chunk.choices ?? [] {
                        if let reasoning = choice.delta?.reasoningContent, !reasoning.isEmpty {
                            continuation.yield(.reasoning(reasoning))
                        }
                        if let text = choice.delta?.content, !text.isEmpty {
                            continuation.yield(.delta(text))
                        }
                        if let reason = choice.finishReason { finishReason = reason }
                    }
                }
            }
            if !finished {
                continuation.yield(.finished(reason: finishReason, usage: usage))
            }
        } catch is CancellationError {
            log.log(.debug, "stream cancelled")
        } catch let error as ProviderError {
            continuation.yield(.error(error))
        } catch {
            log.log(.error, "stream failed: \(error.localizedDescription)")
            continuation.yield(.error(.transport(error.localizedDescription)))
        }
    }

    /// Opens the connection, maps a non-2xx reply to `ProviderError.server`,
    /// and hands back parsed SSE items as they arrive.
    func eventStream(_ request: URLRequest) async throws -> AsyncThrowingStream<SSEItem, any Error> {
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
                    for item in parser.feed(line) { continuation.yield(item) }
                    for item in parser.finish() { continuation.yield(item) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
