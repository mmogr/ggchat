import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// A turn on one of the hub's chats: gglib's runs routes, with the run an
// agent run the hub saves to the chat. Same base URL, same key.
extension OpenAICompatibleProvider {
    /// `PUT runs/{id}?kind=agent` with the turn as its whole body. A 404 or a
    /// 405 with neither a run code nor `conversation_not_found` is a hub with
    /// no runs route. A turn with images refused as `invalid_request` is
    /// taken for a gglib from before images, which refuses `images` as a key
    /// it does not know.
    public func startTurn(runID: String, turn: HubTurn) async throws(HubTurnFailure) -> RunStart {
        let body: Data
        do {
            body = try JSONEncoder().encode(turn)
        } catch {
            throw .refused(.decoding("could not encode the turn: \(error)"))
        }
        var request = makeRequest(path: "runs/\(runID)", method: "PUT", body: body)
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "kind", value: "agent")])
        let answer: (Data, HTTPURLResponse)
        do {
            answer = try await perform(request)
        } catch {
            throw Self.turnFailure(error)
        }
        let (data, response) = answer
        guard (200..<300).contains(response.statusCode) else {
            let error = Self.serverError(status: response.statusCode, body: data)
            if [404, 405].contains(response.statusCode), !Self.carriesARunCode(data),
                error.code != HubChatsCode.conversationNotFound
            {
                return .unsupported
            }
            if !turn.images.isEmpty, case .server(400, ProviderError.Code.invalidRequest.rawValue, _) = error {
                throw .takesNoImages
            }
            throw Self.turnFailure(error)
        }
        do {
            return .started(try decode(RunInfo.self, from: data))
        } catch {
            throw .refused(error)
        }
    }

    /// `GET runs/{id}/events?after=N`, each event read as an agent's.
    public func turnEvents(runID: String, after: UInt32) -> AsyncStream<RunEvent> {
        events(ofRun: runID, after: after, as: .agent)
    }

    /// `POST runs/{id}/cancel`.
    public func cancelTurn(runID: String) async throws(ProviderError) -> RunInfo {
        try await cancelRun(id: runID)
    }

    /// What a refused turn means. Only a lost request may have started the
    /// run; every other failure started nothing.
    static func turnFailure(_ error: ProviderError) -> HubTurnFailure {
        switch error {
        case .server(422, HubChatsCode.noModel, _): .noModel
        case .server(409, RunCode.conflict, _): .replyInProgress
        case .server(404, HubChatsCode.conversationNotFound, _): .chatGone
        case .server(400, ProviderError.Code.attachmentNotFound.rawValue, _): .imageGone
        case .transport: .lost(error)
        case .server, .stream, .decoding, .invalidResponse: .refused(error)
        }
    }

    /// What one of an agent run's events means for the reply: its text, its
    /// reasoning, a line for a tool it calls and the call itself, how far that
    /// tool has got, that it finished, what it answered and the images it
    /// made, a wait for something else, what a
    /// finished model call counted, and an error it reports. The rest, and an
    /// event this build cannot read, mean nothing here: the run's last
    /// report says how it ended, and the hub saves the reply.
    ///
    /// `tool_call_writing` is a call the model is still writing, before its
    /// `tool_call_start`: a line with the tool's name and how many pieces of
    /// the reply's calls have streamed, in `locale`'s digits (`writingLine`), which
    /// the next tool line takes the place of. gglib sends it at the first
    /// named piece and then at most once a second, or, for a model that
    /// writes its calls as text, once when the call is whole. A run cut off
    /// while a call is written ends with an `error`, read as any other.
    ///
    /// `turn_usage` carries its counts flat, under the names a chat stream's
    /// `usage` gives them, so it is read as one.
    static func agentEvents(_ event: SSEEvent, in locale: Locale = .autoupdatingCurrent) -> [ChatEvent] {
        let data = Data(event.data.utf8)
        guard let agent = try? JSONDecoder().decode(AgentEvent.self, from: data) else { return [] }
        switch agent.type {
        case "turn_usage":
            guard let usage = try? JSONDecoder().decode(Usage.self, from: data) else { return [] }
            return [.usage(usage, reason: agent.finishReason)]
        case "text_delta": return agent.content.map { [.delta($0)] } ?? []
        case "reasoning_delta": return agent.content.map { [.reasoning($0)] } ?? []
        case "tool_call_start":
            let line = agent.displayName.map { name in agent.argsSummary.map { "\(name): \($0)" } ?? name }
            return (line.map { [.tool($0)] } ?? []) + (ToolFrames.call(in: data).map { [.toolCalled($0)] } ?? [])
        case "tool_call_writing":
            guard let writing = read(ToolCallWriting.self, data) else { return [] }
            return [.tool(writingLine(writing.displayName, tokens: writing.tokens, in: locale), writing: true)]
        case "tool_call_complete": return finishedTool(data)
        case "tool_progress": return read(ToolProgress.self, data).map { [.toolProgress($0)] } ?? []
        case "waiting": return read(RunWait.self, data).map { [.waiting($0)] } ?? []
        case "error": return [.error(.stream(code: nil, message: agent.message ?? "the reply failed"))]
        default: return []
        }
    }

    /// The line for a call the model is still writing: “Writing Generate
    /// Image… 512 tokens”, the count in `locale`'s digits, or without one
    /// when the frame has none.
    static func writingLine(_ name: String, tokens: Int?, in locale: Locale) -> String {
        guard let tokens else { return "Writing \(name)…" }
        let count = tokens.formatted(.number.locale(locale))
        return "Writing \(name)… \(count) \(tokens == 1 ? "token" : "tokens")"
    }

    /// One event's data as `type`, or nil when it does not read as one: a
    /// stage or a reason this build does not know means nothing here.
    private static func read<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    /// A finished tool: that its call ended, by `result.tool_call_id`, what
    /// it answered, `result.content`, as it came, with whether it failed,
    /// the opposite of `result.success`, and then the images it made,
    /// `result.images`, gglib's `AttachmentInfo` each, under the same call
    /// id, which gglib leaves out when there are none. Images that cannot
    /// be read are passed over and the call has still ended; a result with
    /// no call id means nothing here.
    private static func finishedTool(_ data: Data) -> [ChatEvent] {
        guard let complete = try? JSONDecoder().decode(ToolCallComplete.self, from: data) else { return [] }
        let images = complete.result.images ?? []
        let id = complete.result.callID
        let failed = complete.result.success.map { !$0 }
        let answer =
            complete.result.content.map { [ChatEvent.toolAnswered(callID: id, text: $0, failed: failed)] } ?? []
        return [.toolEnded(id)] + answer + (images.isEmpty ? [] : [.images(images, callID: id)])
    }
}

/// The part of gglib's `tool_call_complete` this device reads.
private struct ToolCallComplete: Decodable {
    struct Result: Decodable {
        let callID: String
        let content: String?
        let success: Bool?
        let images: [ImageRef]?

        enum CodingKeys: String, CodingKey {
            case callID = "tool_call_id"
            case content, success, images
        }

        /// Images that do not read are none, not a result that does not, and
        /// a `success` that does not read is not known.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            callID = try container.decode(String.self, forKey: .callID)
            content = try? container.decodeIfPresent(String.self, forKey: .content)
            success = try? container.decodeIfPresent(Bool.self, forKey: .success)
            images = try? container.decodeIfPresent([ImageRef].self, forKey: .images)
        }
    }

    let result: Result
}

/// The part of gglib's `tool_call_writing` this device reads: the tool's
/// name to show and how many pieces of the reply's calls have streamed. A count that
/// does not read is none, not a frame that does not.
private struct ToolCallWriting: Decodable {
    let displayName: String
    let tokens: Int?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case tokens
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        tokens = try? container.decodeIfPresent(Int.self, forKey: .tokens)
    }
}

/// The parts of gglib's `AgentEvent` this device reads.
private struct AgentEvent: Decodable {
    let type: String
    let content: String?
    let displayName: String?
    let argsSummary: String?
    let message: String?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case displayName = "display_name"
        case argsSummary = "args_summary"
        case message
        case finishReason = "finish_reason"
    }
}
