import Foundation
import SwiftData

/// SwiftData rows. They mirror the Core value types field for field, but for
/// `ProviderRecord`'s last-heard time and a paired Mac's titles last seen, and
/// never leave this directory;
/// `SwiftDataStore` converts both ways. The key is `uuid`, not `id`: a
/// property named `id` shadows PersistentModel's own and a predicate on it
/// traps at fetch time.
@Model
public final class ProviderRecord {
    @Attribute(.unique) public var uuid: UUID
    public var name: String
    public var kindData: Data
    public var defaultModel: String?
    public var createdAt: Date
    /// When this provider's machine was last heard, or nil. Not part of
    /// `ProviderConfig`: saving a config never writes it, so an edit made
    /// from a copy read earlier cannot put an older time back. Optional, so a
    /// store written before it existed opens with every row reading nil.
    public var lastHeard: Date?
    /// The titles a paired Mac's list last showed, as JSON of `[SeenHubChat]`,
    /// and when it was read; nil until a list is. Never a chat's text (ADR
    /// 0007). Kept off `ProviderConfig` and optional, for `lastHeard`'s
    /// reasons.
    public var hubChatsData: Data?
    public var hubSeenAt: Date?
    /// The runs in which a paired Mac is writing replies this device sent
    /// for, as JSON of `[HeldHubRun]`, or nil: a run's id and its chat's,
    /// never a reply's text. Optional, for `lastHeard`'s reasons.
    public var hubLiveRunsData: Data?

    public init(
        id: UUID, name: String, kindData: Data, defaultModel: String?, createdAt: Date, lastHeard: Date? = nil
    ) {
        self.uuid = id
        self.name = name
        self.kindData = kindData
        self.defaultModel = defaultModel
        self.createdAt = createdAt
        self.lastHeard = lastHeard
    }
}

@Model
public final class ConversationRecord {
    @Attribute(.unique) public var uuid: UUID
    public var title: String
    public var providerID: UUID?
    public var model: String?
    /// The conversation's system prompt, or nil. Optional, so SwiftData's
    /// lightweight migration adds it to a store written before it existed,
    /// with every row reading nil. A non-optional attribute would fail that
    /// migration, and the store would fall back to memory, logged and with a
    /// notice for the window to show.
    public var systemPrompt: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Whether the conversation has a reply nobody has opened it to see, or
    /// nil, which reads as no. Optional, for `systemPrompt`'s reason.
    public var hasUnreadReply: Bool?
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    public var messages: [MessageRecord] = []

    public init(
        id: UUID, title: String, providerID: UUID?, model: String?, createdAt: Date, updatedAt: Date,
        systemPrompt: String? = nil, hasUnreadReply: Bool? = nil
    ) {
        self.uuid = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.systemPrompt = systemPrompt
        self.hasUnreadReply = hasUnreadReply
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class MessageRecord {
    @Attribute(.unique) public var uuid: UUID
    public var role: String
    public var content: String
    public var reasoning: String?
    public var isPartial: Bool
    /// The `Failure` that ended this turn early, as JSON, or nil. Optional,
    /// so SwiftData's lightweight migration adds it to a store written before
    /// it existed, with every row reading nil.
    public var failureData: Data?
    /// The run a hub is still writing this reply in, and the last of its
    /// events the row holds, or nil. Optional, for `failureData`'s reason.
    public var runID: String?
    public var runCursor: Int?
    public var createdAt: Date
    public var order: Int
    public var conversation: ConversationRecord?

    public init(
        id: UUID, role: String, content: String, reasoning: String?, isPartial: Bool, createdAt: Date, order: Int,
        failureData: Data? = nil, runID: String? = nil, runCursor: Int? = nil
    ) {
        self.uuid = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.isPartial = isPartial
        self.failureData = failureData
        self.runID = runID
        self.runCursor = runCursor
        self.createdAt = createdAt
        self.order = order
    }
}
