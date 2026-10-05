// A turn this device adds to one of the hub's chats, and the ways the hub
// refuses one.
//
// Written by hand to mirror `gglib_core::domain::hub_chats::HubTurn` in
// gglib. The bodies gglib records under `turn`, `image_turn` and
// `thinking_turn` in `contracts/chats/recorded.json` are replayed against it
// by `HubChatsWireTests`.

/// The user's new message on one of the hub's chats, and nothing else: the
/// hub rebuilds the history from its own record, and refuses a body with a
/// key it does not know.
public struct HubTurn: Codable, Sendable, Equatable {
    /// The chat's id on the hub.
    public let conversationID: Int64
    /// The text, which may be empty when the turn carries images.
    public let content: String
    /// The ids of the images the turn carries, in order, each one the hub
    /// already holds from `POST attachments`. Left out of the body when there
    /// are none, so a turn of text alone is the two keys it always was.
    public let images: [String]
    /// The chat's Thinking choice, said only on the turn that changes it.
    /// Left out of the body when nil: the turn then runs as the hub
    /// remembers, and a hub from before the key, which would refuse it, is
    /// never sent it.
    public let thinking: HubThinking?

    public init(conversationID: Int64, content: String, images: [String] = [], thinking: HubThinking? = nil) {
        self.conversationID = conversationID
        self.content = content
        self.images = images
        self.thinking = thinking
    }

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case content
        case images
        case thinking
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(Int64.self, forKey: .conversationID)
        content = try container.decode(String.self, forKey: .content)
        images = try container.decodeIfPresent([String].self, forKey: .images) ?? []
        thinking = try container.decodeIfPresent(HubThinking.self, forKey: .thinking)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(content, forKey: .content)
        if !images.isEmpty { try container.encode(images, forKey: .images) }
        try container.encodeIfPresent(thinking, forKey: .thinking)
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
    /// The hub does not hold an image the turn names: `400
    /// attachment_not_found`. The refusal started no run, so the same turn,
    /// its images sent again, can be put under the same id.
    case imageGone
    /// The hub's gglib is from before images: it has no `attachments` route,
    /// or refuses a turn's `images` as a key it does not know.
    case takesNoImages
    /// Any other refusal, a 5xx, or an answer that cannot be read.
    case refused(ProviderError)
    /// The request or its answer was lost on the way, so the run may have
    /// started. Asking again under the same id answers with it if it did.
    case lost(ProviderError)
}
