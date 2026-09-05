import Foundation

public enum Role: String, Codable, Sendable, Equatable, Hashable {
    case system
    case user
    case assistant
}

/// One turn. `reasoning` holds a reasoning model's thinking, shown collapsed.
/// `isPartial` means the reply stopped before the model finished, by the user
/// or by the connection; the UI offers Continue.
public struct Message: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var role: Role
    public var content: String
    public var reasoning: String?
    public var isPartial: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        reasoning: String? = nil,
        isPartial: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.isPartial = isPartial
        self.createdAt = createdAt
    }
}

public struct Conversation: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var providerID: UUID?
    public var model: String?
    public var messages: [Message]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        providerID: UUID? = nil,
        model: String? = nil,
        messages: [Message] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The first line of the first user message, or empty.
    public var derivedTitle: String {
        guard let first = messages.first(where: { $0.role == .user }) else { return "" }
        let line = first.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.prefix(80))
    }
}
