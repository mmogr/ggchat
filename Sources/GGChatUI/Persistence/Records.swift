import Foundation
import SwiftData

/// SwiftData rows. They mirror the Core value types field for field and
/// never leave this directory; `SwiftDataStore` converts both ways. The key
/// is `uuid`, not `id`: a property named `id` shadows PersistentModel's own
/// and a predicate on it traps at fetch time.
@Model
public final class ProviderRecord {
    @Attribute(.unique) public var uuid: UUID
    public var name: String
    public var kindData: Data
    public var defaultModel: String?
    public var createdAt: Date

    public init(id: UUID, name: String, kindData: Data, defaultModel: String?, createdAt: Date) {
        self.uuid = id
        self.name = name
        self.kindData = kindData
        self.defaultModel = defaultModel
        self.createdAt = createdAt
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
    /// migration, and the store would fall back to memory without a word.
    public var systemPrompt: String?
    public var createdAt: Date
    public var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    public var messages: [MessageRecord] = []

    public init(
        id: UUID, title: String, providerID: UUID?, model: String?, createdAt: Date, updatedAt: Date,
        systemPrompt: String? = nil
    ) {
        self.uuid = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.systemPrompt = systemPrompt
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
    public var createdAt: Date
    public var order: Int
    public var conversation: ConversationRecord?

    public init(
        id: UUID, role: String, content: String, reasoning: String?, isPartial: Bool, createdAt: Date, order: Int,
        failureData: Data? = nil
    ) {
        self.uuid = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.isPartial = isPartial
        self.failureData = failureData
        self.createdAt = createdAt
        self.order = order
    }
}
