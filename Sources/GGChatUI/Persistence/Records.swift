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
    /// The conversation's `ContextReading` as JSON, or nil: the counts its
    /// last finished reply left, never any text. Optional, for
    /// `systemPrompt`'s reason.
    public var contextData: Data?
    /// Whether the conversation asks its model not to think, or nil, which
    /// reads as no. Optional, for `systemPrompt`'s reason.
    public var thinkingOff: Bool?
    /// The conversation this one was branched from, and the first of its
    /// family, or nil for one started here (ADR 0010). Optional, for
    /// `systemPrompt`'s reason.
    public var branchOf: UUID?
    public var family: UUID?
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    public var messages: [MessageRecord] = []

    public init(
        id: UUID, title: String, providerID: UUID?, model: String?, createdAt: Date, updatedAt: Date,
        systemPrompt: String? = nil, hasUnreadReply: Bool? = nil, contextData: Data? = nil,
        thinkingOff: Bool? = nil, branchOf: UUID? = nil, family: UUID? = nil
    ) {
        self.uuid = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.systemPrompt = systemPrompt
        self.hasUnreadReply = hasUnreadReply
        self.contextData = contextData
        self.thinkingOff = thinkingOff
        self.branchOf = branchOf
        self.family = family
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
    /// The images the turn carries, in order, as JSON of `[ImageRef]`: each
    /// one's id, type and size, never its bytes, which are the `ImageRecord`
    /// under the same id. Nil for a turn with none. Optional, for
    /// `failureData`'s reason.
    public var imagesData: Data?
    /// The message this one copies as first written, when a branch copied
    /// it, or nil (ADR 0010). Optional, for `failureData`'s reason.
    public var originID: UUID?
    public var createdAt: Date
    public var order: Int
    public var conversation: ConversationRecord?

    public init(
        id: UUID, role: String, content: String, reasoning: String?, isPartial: Bool, createdAt: Date, order: Int,
        failureData: Data? = nil, runID: String? = nil, runCursor: Int? = nil, imagesData: Data? = nil,
        originID: UUID? = nil
    ) {
        self.uuid = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.isPartial = isPartial
        self.failureData = failureData
        self.runID = runID
        self.runCursor = runCursor
        self.imagesData = imagesData
        self.originID = originID
        self.createdAt = createdAt
        self.order = order
    }
}

/// An image's bytes, kept once under the SHA-256 they hash to however many
/// turns name it. The bytes are external storage: SwiftData writes a large
/// value to a file in a folder beside the store rather than into it, and a
/// reset removes that folder with the store (`StoreDirectory`). A row is
/// deleted with the last turn that names it (`SwiftDataStore+Images`). The
/// key is `imageID` for `uuid`'s reason.
@Model
public final class ImageRecord {
    @Attribute(.unique) public var imageID: String
    public var mime: String
    public var width: Int
    public var height: Int
    @Attribute(.externalStorage) public var data: Data

    public init(imageID: String, mime: String, width: Int, height: Int, data: Data) {
        self.imageID = imageID
        self.mime = mime
        self.width = width
        self.height = height
        self.data = data
    }
}
