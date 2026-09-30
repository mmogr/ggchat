import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// gglib's chats routes, beside its runs routes. Same base URL, same key.
extension OpenAICompatibleProvider: HubChatsProvider {
    /// `GET chats`.
    public func listChats() async throws(HubChatsFailure) -> HubChatList {
        try await readHub(HubChatList.self, at: "chats")
    }

    /// `GET chats/{id}`.
    public func openChat(id: Int64) async throws(HubChatsFailure) -> HubChatOpen {
        try await readHub(HubChatOpen.self, at: "chats/\(id)")
    }

    private func readHub<T: Decodable>(_ type: T.Type, at path: String) async throws(HubChatsFailure) -> T {
        let request = makeRequest(path: path, method: "GET", body: nil)
        let answer: (Data, HTTPURLResponse)
        do {
            answer = try await perform(request)
        } catch {
            throw Self.hubFailure(error)
        }
        let (data, response) = answer
        guard (200..<300).contains(response.statusCode) else {
            throw Self.hubFailure(Self.serverError(status: response.statusCode, body: data))
        }
        // The hub always answers JSON. A captive portal or a relay's page in
        // front of it does not, and the hub is still there once reached.
        guard response.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true else {
            throw .dropped(.invalidResponse("the answer was not JSON"))
        }
        do {
            return try decode(type, from: data)
        } catch {
            throw .refused(error)
        }
    }

    /// What a failed read of the hub's chats means, as a run's read does: a
    /// 404 is no such chat, any other 4xx or a body that cannot be read is a
    /// refusal, and the rest is a drop. `device_not_named` has its own case.
    static func hubFailure(_ error: ProviderError) -> HubChatsFailure {
        switch error {
        case .server(403, HubChatsCode.deviceNotNamed, _): .notShared
        case .server(404, _, _): .notFound
        case .server(let status, _, _) where (400..<500).contains(status): .refused(error)
        case .decoding: .refused(error)
        case .server, .stream, .transport, .invalidResponse: .dropped(error)
        }
    }
}
