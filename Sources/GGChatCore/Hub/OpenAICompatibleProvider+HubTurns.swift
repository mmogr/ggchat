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
    /// reasoning, a line for a tool it calls, and an error it reports. The
    /// rest, and an event this build cannot read, mean nothing here: the
    /// run's last report says how it ended, and the hub saves the reply.
    static func agentEvents(_ event: SSEEvent) -> [ChatEvent] {
        guard let agent = try? JSONDecoder().decode(AgentEvent.self, from: Data(event.data.utf8)) else { return [] }
        switch agent.type {
        case "text_delta": return agent.content.map { [.delta($0)] } ?? []
        case "reasoning_delta": return agent.content.map { [.reasoning($0)] } ?? []
        case "tool_call_start":
            guard let name = agent.displayName else { return [] }
            return [.tool(agent.argsSummary.map { "\(name): \($0)" } ?? name)]
        case "error": return [.error(.stream(code: nil, message: agent.message ?? "the reply failed"))]
        default: return []
        }
    }
}

/// The parts of gglib's `AgentEvent` this device reads.
private struct AgentEvent: Decodable {
    let type: String
    let content: String?
    let displayName: String?
    let argsSummary: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case displayName = "display_name"
        case argsSummary = "args_summary"
        case message
    }
}
