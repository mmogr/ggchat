// The Thinking choice of a chat the hub keeps: what a turn says of it, and
// what the opened chat says the hub remembers.
//
// Written by hand to mirror `gglib_core::domain::thinking::Thinking` and the
// two fields of `ConversationSettings` this app reads. The bodies gglib
// records under `thinking_turn` and the opened chat's `settings` in
// `contracts/chats/recorded.json` are replayed against these by
// `HubChatsWireTests`.

/// What a turn says of its chat's Thinking choice, on the turn that changes
/// it: the hub remembers `off` on the chat and forgets it at `default`.
public enum HubThinking: String, Codable, Sendable, Equatable {
    /// Run this turn and the chat's later ones with no thinking.
    case off
    /// Think as the model would with nothing said.
    case `default`
}

/// The two of an opened chat's settings this app reads. The rest are the
/// hub's own and are passed over.
public struct HubChatSettings: Codable, Sendable, Equatable {
    /// `off` while the hub remembers the chat's thinking switched off. The
    /// hub stores no other word, and leaves the key out otherwise.
    public let thinking: HubThinking?
    /// The model the chat's last run used, as the hub's model list names it.
    public let modelName: String?

    public init(thinking: HubThinking? = nil, modelName: String? = nil) {
        self.thinking = thinking
        self.modelName = modelName
    }

    enum CodingKeys: String, CodingKey {
        case thinking
        case modelName = "model_name"
    }

    /// Either that does not read costs only itself, so a word this build
    /// does not know leaves the model's name readable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thinking = try? container.decodeIfPresent(HubThinking.self, forKey: .thinking)
        modelName = try? container.decodeIfPresent(String.self, forKey: .modelName)
    }
}
