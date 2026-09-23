import Foundation

public enum Role: String, Codable, Sendable, Equatable, Hashable {
    case system
    case user
    case assistant
}

/// One turn. `reasoning` holds a reasoning model's thinking, shown collapsed.
/// `isPartial` means the reply stopped before the model finished, by the user
/// or by the connection; the UI offers Continue. `failure` is what ended the
/// turn early when something said so, kept on the message that ended it.
public struct Message: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var role: Role
    public var content: String
    public var reasoning: String?
    public var isPartial: Bool
    public var failure: Failure?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        reasoning: String? = nil,
        isPartial: Bool = false,
        failure: Failure? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.isPartial = isPartial
        self.failure = failure
        self.createdAt = createdAt
    }
}

/// Why a turn ended without the model finishing it, kept on the message
/// that ended it: the question when nothing arrived, the partial reply when
/// some of it did. A refusal before the first token has no reply to sit
/// under, and a sentence kept only in memory is gone after a relaunch.
///
/// What the error said (the server's own sentence, or this app's sentence
/// about a connection that failed), its code and the side to look at. Not
/// the hint: that is worked out when it is drawn, from the code where this
/// build knows it, so a better one reaches old conversations too. The side
/// is kept for the failures with no such code, a transport error say.
public struct Failure: Codable, Sendable, Equatable, Hashable {
    public var message: String
    public var code: String?
    public var whereToLook: WhereToLook

    public init(message: String, code: String?, whereToLook: WhereToLook) {
        self.message = message
        self.code = code
        self.whereToLook = whereToLook
    }

    public init(_ error: ProviderError) {
        self.init(
            message: error.errorDescription ?? "The request failed.", code: error.code,
            whereToLook: error.whereToLook)
    }

    /// The second line under it, as ``ProviderError/hint`` would give it.
    public var hint: String? {
        ProviderError.hint(forCode: code, on: whereToLook)
    }

    private enum CodingKeys: String, CodingKey {
        case message, code, whereToLook
    }

    /// A side this build does not know reads as `.unknown` instead of failing
    /// the whole value: the sentence is what matters, and a conversation
    /// saved by a later build must not lose it over the line under it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        let side = try container.decodeIfPresent(String.self, forKey: .whereToLook)
        whereToLook = side.flatMap(WhereToLook.init(rawValue:)) ?? .unknown
    }
}

public struct Conversation: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var providerID: UUID?
    public var model: String?
    public var messages: [Message]
    /// What the model is told ahead of every request, or nil for nothing. A
    /// setting of the conversation and never a turn in it: it is not in
    /// `messages`, so it is never drawn and never stored as one, and an edit
    /// reaches the next request, Continue included (ADR 0005).
    public var systemPrompt: String?
    public var createdAt: Date
    public var updatedAt: Date

    /// The id the system turn carries in `requestMessages`. Fixed rather than
    /// a fresh `UUID()`, so two requests built from the same conversation are
    /// equal; the turn is never stored, so no saved message can share it.
    public static let systemPromptMessageID = UUID(uuidString: "5E575E00-0000-4000-8000-000000000000")!

    public init(
        id: UUID = UUID(),
        title: String = "",
        providerID: UUID? = nil,
        model: String? = nil,
        messages: [Message] = [],
        systemPrompt: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Whether there is a system prompt to send. Blank counts as none, so a
    /// prompt of only spaces sends nothing rather than an empty turn.
    public var hasSystemPrompt: Bool {
        guard let systemPrompt else { return false }
        return !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The turns a request carries: the system prompt first when there is
    /// one, then the transcript. Built here and nowhere else, so send,
    /// Continue and Retry all send the same prompt. The system turn is dated
    /// `createdAt` rather than now, so building it twice gives the same value.
    public var requestMessages: [Message] {
        guard hasSystemPrompt, let systemPrompt else { return messages }
        let system = Message(
            id: Self.systemPromptMessageID, role: .system, content: systemPrompt, createdAt: createdAt)
        return [system] + messages
    }

    /// The first line of the first user message, or empty.
    public var derivedTitle: String {
        guard let first = messages.first(where: { $0.role == .user }) else { return "" }
        let line = first.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.prefix(80))
    }
}
