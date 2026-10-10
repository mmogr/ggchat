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
/// `runID` names the run on the hub still writing this reply, and
/// `runCursor` the last of its events this message holds; both are nil once
/// the reply is no longer being written there. `images` names the images the
/// turn carries, in order; their bytes are kept apart, by id: a question's
/// are the ones sent with it, and a reply's the ones a tool made for it.
/// `originID` is the message this one copies as first written, when a branch
/// copied it (ADR 0010), and nil for a message written here.
/// `draws` is a question sent with Draw pressed to a hub that could draw:
/// its reply may have a picture made, and Retry asks for one again.
/// `runFrames` is how the run named by `runID` writes its events, when not
/// as the chat route's chunks, so a reply read on is read with the decoder
/// its run needs; nil with `runID`, and for a run of chunks.
public struct Message: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var role: Role
    public var content: String
    public var reasoning: String?
    public var isPartial: Bool
    public var failure: Failure?
    public var createdAt: Date
    public var runID: String?
    public var runCursor: UInt32?
    public var images: [ImageRef]
    public var originID: UUID?
    public var draws: Bool
    public var runFrames: RunFrames?

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        reasoning: String? = nil,
        isPartial: Bool = false,
        failure: Failure? = nil,
        createdAt: Date,
        runID: String? = nil,
        runCursor: UInt32? = nil,
        images: [ImageRef] = [],
        originID: UUID? = nil,
        draws: Bool = false,
        runFrames: RunFrames? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.isPartial = isPartial
        self.failure = failure
        self.createdAt = createdAt
        self.runID = runID
        self.runCursor = runCursor
        self.images = images
        self.originID = originID
        self.draws = draws
        self.runFrames = runFrames
    }

    /// Whether a hub is still writing this reply, away from this device.
    public var isBeingWritten: Bool {
        runID != nil
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
    /// Whether a reply ended here, finished, failed or given up, while
    /// another conversation was the one open, and this one has not been
    /// opened since. Kept on this device only.
    public var hasUnreadReply: Bool
    /// How much of its model's context the conversation used at the last
    /// finished reply, or nil when the server reported no context size. A
    /// reply that stops or fails leaves it as it was.
    public var context: ContextReading?
    /// Whether the model is asked not to think in this conversation. A
    /// setting of the conversation, as its system prompt is, sent with each
    /// request to gglib alone, and not for a model its list names as not
    /// thinking (ADR 0009).
    public var thinkingOff: Bool
    /// The conversation this one was branched from, and the first of its
    /// family, when it is a branch (ADR 0010); both nil for one started here.
    /// They are kept even when those conversations are deleted.
    public var branchOf: UUID?
    public var family: UUID?

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
        updatedAt: Date,
        hasUnreadReply: Bool = false,
        context: ContextReading? = nil,
        thinkingOff: Bool = false,
        branchOf: UUID? = nil,
        family: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hasUnreadReply = hasUnreadReply
        self.context = context
        self.thinkingOff = thinkingOff
        self.branchOf = branchOf
        self.family = family
    }

    /// The family the conversation is one of: the first conversation's id,
    /// its own when it is that one.
    public var familyID: UUID {
        family ?? id
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

    /// The first line of the first user message, or empty. A first turn of
    /// images alone is called what it holds.
    public var derivedTitle: String {
        guard let first = messages.first(where: { $0.role == .user }) else { return "" }
        let line = first.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if line.isEmpty, !first.images.isEmpty {
            return first.images.count == 1 ? "An image" : "\(first.images.count) images"
        }
        return String(line.prefix(80))
    }
}
