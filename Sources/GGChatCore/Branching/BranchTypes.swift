/// Whose a row of a chat is, as the branching rules read it. A question is
/// one user row; a reply is the run of assistant and tool rows after it; a
/// system row belongs to neither.
public enum BranchRole: String, Codable, Sendable, Equatable, Hashable {
    case system
    case user
    case assistant
    case tool
}

/// A saved message as the branching rules read it: its id, whose it is, its
/// text and the ids of the images it carries, in order.
public struct BranchRow<ID: Hashable & Sendable>: Sendable, Equatable {
    public var id: ID
    public var role: BranchRole
    public var content: String
    public var images: [String]

    public init(id: ID, role: BranchRole, content: String, images: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
    }
}

/// A change to a saved chat. One that would discard or alter a saved reply
/// branches the chat into a new identical one and changes that instead
/// (ADR 0010).
public enum ChatChange<ID: Hashable & Sendable>: Sendable, Equatable {
    /// New text for a message: a question, asked again with it and with
    /// `images`, or a reply, kept as written, which carries no image.
    case edit(messageID: ID, content: String, images: [String])
    /// The reply holding this message answered again.
    case regenerate(messageID: ID)
    /// The chat copied, as far as the end of the turn holding this message,
    /// into a new chat to go on in.
    case branch(messageID: ID)

    /// The message the change names.
    public var messageID: ID {
        switch self {
        case .edit(let id, _, _), .regenerate(let id), .branch(let id): id
        }
    }
}

/// What a change writes: the one change made in place, or a branch.
public enum BranchPlan<ID: Hashable & Sendable>: Sendable, Equatable {
    /// The chat's last question, nothing answering it, replaced by the edit.
    case replace(question: ID)
    /// A new chat of the family holding a copy of the chat as far as
    /// `through` (nothing when nil), then what `then` says, and whether its
    /// last question is then to be answered.
    case fork(through: ID?, then: BranchThen, answer: Bool)
}

/// What a branch holds after the rows it copies.
public enum BranchThen: String, Sendable, Equatable {
    /// Nothing more.
    case nothing
    /// The edited question.
    case question
    /// The edited reply, as one message of plain text.
    case editedReply = "edited_reply"
}

/// Why a change was not made. Nothing is written.
public enum BranchRefusal: Error, Sendable, Equatable {
    /// The message is not in the chat.
    case messageNotFound
    /// The edit leaves the message as it was.
    case unchanged
    /// A regenerate names a question; only a reply is answered again.
    case notAReply
    /// The reply answers no question, or the chat ends in no question.
    case nothingToAnswer
    /// An edited reply carries no image.
    case imagesOnReply

    /// The code gglib refuses the same change with.
    public var code: String {
        switch self {
        case .messageNotFound: "message_not_found"
        case .unchanged: "unchanged"
        case .notAReply: "not_a_reply"
        case .nothingToAnswer: "nothing_to_answer"
        case .imagesOnReply: "invalid_request"
        }
    }
}

/// A message of a chat of a family, as the branch points read it. `key` is
/// the message it copies as first written, or its own: two chats that hold
/// the same key at the same place hold the same chat up to there.
public struct LineRow<ID: Hashable & Sendable, Key: Hashable & Comparable & Sendable>: Sendable, Equatable {
    public var id: ID
    public var key: Key
    public var role: BranchRole
    public var text: String
    public var images: Int

    public init(id: ID, key: Key, role: BranchRole, text: String, images: Int = 0) {
        self.id = id
        self.key = key
        self.role = role
        self.text = text
        self.images = images
    }
}

/// A chat of a family: its id, when it last changed, and its rows in order.
public struct LineChat<
    ChatID: Hashable & Comparable & Sendable, ID: Hashable & Sendable, Key: Hashable & Comparable & Sendable,
    Stamp: Comparable & Sendable
>: Sendable, Equatable {
    public var chatID: ChatID
    public var updatedAt: Stamp
    public var rows: [LineRow<ID, Key>]

    public init(chatID: ChatID, updatedAt: Stamp, rows: [LineRow<ID, Key>]) {
        self.chatID = chatID
        self.updatedAt = updatedAt
        self.rows = rows
    }
}

/// One option at a branch point: the chat that holds it, its message there
/// (nil for the open chat's own empty option, a branch with nothing there
/// yet), whose turn it is, and the line it is shown by.
public struct BranchOption<ChatID: Hashable & Sendable, ID: Hashable & Sendable>: Sendable, Equatable, Hashable {
    public var chatID: ChatID
    public var messageID: ID?
    public var role: BranchRole?
    public var preview: String

    public init(chatID: ChatID, messageID: ID?, role: BranchRole?, preview: String) {
        self.chatID = chatID
        self.messageID = messageID
        self.role = role
        self.preview = preview
    }
}

/// A point where a chat's family holds two or more different turns: the
/// chat's message that starts its turn there (nil for the point after its
/// last message), which of `options` the chat is, and every option, the
/// oldest first.
public struct BranchPoint<ChatID: Hashable & Sendable, ID: Hashable & Sendable>: Sendable, Equatable, Hashable {
    public var messageID: ID?
    public var index: Int
    public var options: [BranchOption<ChatID, ID>]

    public init(messageID: ID?, index: Int, options: [BranchOption<ChatID, ID>]) {
        self.messageID = messageID
        self.index = index
        self.options = options
    }
}
