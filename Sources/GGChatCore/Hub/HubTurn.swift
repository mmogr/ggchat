// A turn this device adds to one of the hub's chats, and the ways the hub
// refuses one.
//
// Written by hand to mirror `gglib_core::domain::hub_chats::HubTurn` in
// gglib. The body gglib records under `turn` in `contracts/chats/recorded.json`
// is replayed against it by `HubChatsWireTests`.

/// The user's new message on one of the hub's chats, and nothing else: the
/// hub rebuilds the history from its own record, and refuses a body with any
/// other key.
public struct HubTurn: Codable, Sendable, Equatable {
    /// The chat's id on the hub.
    public let conversationID: Int64
    public let content: String

    public init(conversationID: Int64, content: String) {
        self.conversationID = conversationID
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case content
    }
}

/// Why the hub did not start a turn.
public enum HubTurnFailure: Error, Sendable, Equatable {
    /// Neither the chat nor its last reply names a model, nothing is running
    /// on the Mac and it has no default: `422 no_model`.
    case noModel
    /// A reply to the chat is already being written: `409 conflict`.
    case replyInProgress
    /// The hub has no such chat: `404 conversation_not_found`.
    case chatGone
    /// Any other refusal, a 5xx, or an answer that cannot be read.
    case refused(ProviderError)
    /// The request or its answer was lost on the way, so the run may have
    /// started. Asking again under the same id answers with it if it did.
    case lost(ProviderError)
}
