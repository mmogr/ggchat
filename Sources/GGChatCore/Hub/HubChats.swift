import Foundation

// The wire shapes of the hub's chats: what a paired Mac lists and opens for
// this device through its tunnel.
//
// Written by hand to mirror `gglib_core::domain::hub_chats` in gglib. The
// bodies gglib records in `contracts/chats/recorded.json` are replayed against
// these types by `HubChatsWireTests`, so a change on either side shows there.
//
// Read live and never stored: nothing here is written to this device, but
// the titles the list last saw (ADR 0007). An optional field decodes to `nil`
// whether its key is absent or `null`, and keys this build does not know are
// passed over.

/// One of the hub's chats, as `GET /v1/chats` lists it.
public struct HubChatSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// The conversation's id on the hub.
    public let id: Int64
    public let title: String
    /// The catalogue model it was made with, when it names one.
    public let modelID: Int64?
    /// That model's name, when the catalogue still has it.
    public let model: String?
    /// When it last changed, as the hub's database writes it.
    public let updatedAt: String
    /// The run whose reply to it is not yet saved, if one is.
    public let liveRun: String?

    public init(
        id: Int64, title: String, modelID: Int64? = nil, model: String? = nil, updatedAt: String,
        liveRun: String? = nil
    ) {
        self.id = id
        self.title = title
        self.modelID = modelID
        self.model = model
        self.updatedAt = updatedAt
        self.liveRun = liveRun
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case modelID = "model_id"
        case model
        case updatedAt = "updated_at"
        case liveRun = "live_run"
    }
}

extension HubChatSummary {
    /// Reads a time as the hub's database writes it with `datetime('now')`:
    /// "2026-09-30 09:13:07", in UTC, to the second. Anything else is nil.
    public static func date(fromUpdatedAt text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter.date(from: text)
    }
}

/// The hub's chats, the most recently changed first.
public struct HubChatList: Codable, Sendable, Equatable {
    public let chats: [HubChatSummary]

    public init(chats: [HubChatSummary]) {
        self.chats = chats
    }
}

/// The conversation of an opened chat. Its settings are the hub's own and
/// are not read here.
public struct HubConversation: Codable, Sendable, Equatable {
    public let id: Int64
    public let title: String
    public let modelID: Int64?
    public let systemPrompt: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: Int64, title: String, modelID: Int64? = nil, systemPrompt: String? = nil, createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.modelID = modelID
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case modelID = "model_id"
        case systemPrompt = "system_prompt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// What the hub saved beside a row: which device made the turn, and for a
/// reply the model that wrote it and what its last model call counted. Its
/// other keys are passed over.
public struct HubMessageMetadata: Codable, Sendable, Equatable {
    /// The paired device that made the turn; nil for the hub's own.
    public let device: String?
    public let modelName: String?
    /// The counts a ``ContextReading`` is made of, each nil when the hub did
    /// not save it: unknown, not zero.
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let contextSize: Int?
    public let trimmedMessages: Int?
    /// Why that call ended, as the model's stream said it.
    public let finishReason: String?
    /// The hub's mark on a reply that did not finish.
    public let incomplete: Bool?

    public init(
        device: String? = nil, modelName: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        contextSize: Int? = nil, trimmedMessages: Int? = nil, finishReason: String? = nil, incomplete: Bool? = nil
    ) {
        self.device = device
        self.modelName = modelName
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.contextSize = contextSize
        self.trimmedMessages = trimmedMessages
        self.finishReason = finishReason
        self.incomplete = incomplete
    }

    /// A count, a reason or a mark that does not read costs only itself, so
    /// the row keeps who made it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decodeIfPresent(String.self, forKey: .device)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        promptTokens = try? container.decodeIfPresent(Int.self, forKey: .promptTokens)
        completionTokens = try? container.decodeIfPresent(Int.self, forKey: .completionTokens)
        contextSize = try? container.decodeIfPresent(Int.self, forKey: .contextSize)
        trimmedMessages = try? container.decodeIfPresent(Int.self, forKey: .trimmedMessages)
        finishReason = try? container.decodeIfPresent(String.self, forKey: .finishReason)
        incomplete = try? container.decodeIfPresent(Bool.self, forKey: .incomplete)
    }
}

/// One row of an opened chat.
public struct HubMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let conversationID: Int64
    /// `system`, `user`, `assistant` or `tool`, as the hub writes it.
    public let role: String
    public let content: String
    public let createdAt: String
    public let metadata: HubMessageMetadata?
    /// The images a user's message carries, by reference, in order: each is
    /// read by its id from `GET attachments/{id}` when it is drawn. Nil when
    /// the row carries none.
    public let images: [ImageRef]?

    public init(
        id: Int64, conversationID: Int64, role: String, content: String, createdAt: String,
        metadata: HubMessageMetadata? = nil, images: [ImageRef]? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.metadata = metadata
        self.images = images
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case role
        case content
        case createdAt = "created_at"
        case metadata
        case images
    }

    /// Metadata is whatever the hub saved beside the row, so metadata this
    /// build cannot read costs the row its metadata, not the whole chat.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        conversationID = try container.decode(Int64.self, forKey: .conversationID)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        metadata = try? container.decodeIfPresent(HubMessageMetadata.self, forKey: .metadata)
        images = try container.decodeIfPresent([ImageRef].self, forKey: .images)
    }
}

/// One chat opened: the conversation and its rows, oldest first.
public struct HubChatOpen: Codable, Sendable, Equatable {
    public let conversation: HubConversation
    public let messages: [HubMessage]

    public init(conversation: HubConversation, messages: [HubMessage]) {
        self.conversation = conversation
        self.messages = messages
    }
}
