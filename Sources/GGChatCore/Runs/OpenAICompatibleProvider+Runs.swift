import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// How the data of a run's numbered events is written: as the chat route's
/// chunks, or as gglib's agent events.
enum RunFrames: Sendable {
    case chat
    case agent
}

// gglib's runs routes, beside the chat route they replace for a hub that has
// them. Same base URL, same key.
extension OpenAICompatibleProvider: RunProvider {
    /// `PUT runs/{id}` with the body `chat/completions` would be sent.
    /// A 404 or a 405 with no run code is a hub without the route.
    public func startRun(id: String, _ chatRequest: ChatRequest) async throws(ProviderError) -> RunStart {
        let body: Data
        do {
            body = try JSONEncoder().encode(ChatCompletionRequest(chatRequest))
        } catch {
            throw .decoding("could not encode the request: \(error)")
        }
        let request = makeRequest(path: "runs/\(id)", method: "PUT", body: body)
        let (data, response) = try await perform(request)
        if [404, 405].contains(response.statusCode), !Self.carriesARunCode(data) { return .unsupported }
        try checkStatus(response, data: data)
        return .started(try decode(RunInfo.self, from: data))
    }

    /// `GET runs/{id}/events?after=N`, read until `event: run` or the end.
    public func runEvents(id: String, after: UInt32) -> AsyncStream<RunEvent> {
        events(ofRun: id, after: after, as: .chat)
    }

    /// A run's events, each read as `frames` says its data is written.
    func events(ofRun id: String, after: UInt32, as frames: RunFrames) -> AsyncStream<RunEvent> {
        AsyncStream { continuation in
            let task = Task {
                if let end = await self.readRun(id, after: after, as: frames, into: continuation) {
                    continuation.yield(end)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `POST runs/{id}/cancel`.
    public func cancelRun(id: String) async throws(ProviderError) -> RunInfo {
        let request = makeRequest(path: "runs/\(id)/cancel", method: "POST", body: nil)
        let (data, response) = try await perform(request)
        try checkStatus(response, data: data)
        return try decode(RunInfo.self, from: data)
    }

    /// Passes on each numbered event above `after` as one frame, and returns
    /// how the stream ended, or nil when the reader was cancelled.
    ///
    /// An event numbered at or below the last one passed on is dropped, so a
    /// hub that sends one twice, or from further back than it was asked, has
    /// no event applied twice.
    ///
    /// A `preview` is read by its name, ahead of the numbering: it is not
    /// one of the run's numbered events, and whatever id came with it or
    /// before it, it moves no cursor. One that does not read is passed over.
    private func readRun(
        _ id: String, after: UInt32, as frames: RunFrames, into continuation: AsyncStream<RunEvent>.Continuation
    ) async -> RunEvent? {
        var request = makeRequest(path: "runs/\(id)/events", method: "GET", body: nil)
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "after", value: String(after))])
        var cursor = after
        var reply = ReplyState()
        reply.yieldsUsage = true
        do {
            let items = try await eventStream(
                request, over: streamingSession, flushingAtEnd: false, requiringEventStream: true)
            for try await item in items {
                guard case .event(let event) = item else { continue }
                if event.event == "run" {
                    return .ended(try decode(RunInfo.self, from: Data(event.data.utf8)))
                }
                if event.event == "preview" {
                    if let frame = try? JSONDecoder().decode(PreviewFrame.self, from: Data(event.data.utf8)) {
                        continuation.yield(.preview(frame))
                    }
                    continue
                }
                guard let seq = event.id.flatMap(UInt32.init), seq > cursor else { continue }
                cursor = seq
                let events = frames == .chat ? frame(event, into: &reply) : Self.agentEvents(event)
                continuation.yield(.frame(seq: seq, events: events))
            }
            return .dropped(nil)
        } catch is CancellationError {
            return nil
        } catch let error as ProviderError {
            return Self.end(of: error)
        } catch {
            return Task.isCancelled ? nil : .dropped(.transport(error.localizedDescription))
        }
    }

    /// What one numbered event means for the reply, as the chat route reads
    /// it. An in-stream error is passed on and the reading goes on: the run's
    /// last report, not the error, says how it ended.
    private func frame(_ event: SSEEvent, into reply: inout ReplyState) -> [ChatEvent] {
        switch read(event, into: &reply) {
        case .yield(let events): events
        case .skip: []
        case .end(let events, let failure): events + [.error(failure)]
        }
    }

    /// How a read that failed with `error` ends: a 404 is a run the hub does
    /// not have, any other 4xx, or a report the hub sent that cannot be read,
    /// is a refusal, and the rest is a drop: a 5xx, no answer at all, or a
    /// 2xx that is not an event stream. The hub never sends that last one; a
    /// captive portal or a relay's page in front of it does, and the run is
    /// still there once the hub can be reached.
    static func end(of error: ProviderError) -> RunEvent {
        switch error {
        case .server(404, _, _): .notFound
        case .server(let status, _, _) where (400..<500).contains(status): .refused(error)
        case .decoding: .refused(error)
        case .server, .stream, .transport, .invalidResponse: .dropped(error)
        }
    }

    /// Whether an error body names one of the runs routes' own codes.
    static func carriesARunCode(_ body: Data) -> Bool {
        guard let parsed = try? JSONDecoder().decode(APIErrorBody.self, from: body), let code = parsed.error.code
        else { return false }
        return RunCode.all.contains(code)
    }
}
