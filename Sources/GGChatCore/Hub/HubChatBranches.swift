import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// A Mac's chats and their branches (ADR 0010): the branch points an opened
// chat says, a change this device asks the Mac to make, and its answer.
//
// Written by hand to mirror gglib's `ChatChange`, `ChatChanged` and
// `BranchPoint` from gglib pull request #1380, and replayed by
// `HubChatBranchesWireTests` against the bodies gglib records under `branch_open`,
// `change`, `changed` and `answer_turn` in `contracts/chats/recorded.json`.
// Nothing of a Mac's chat is copied here: the Mac makes the change and
// keeps the branch (ADR 0007).

/// A change this device asks a Mac to make to one of its chats, as
/// `POST /v1/chats/{id}/changes` takes it: the body the Mac's own page sends.
public struct HubChatChange: Encodable, Sendable, Equatable {
    public let change: ChatChange<Int64>

    public init(_ change: ChatChange<Int64>) {
        self.change = change
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case messageID = "message_id"
        case content
        case images
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(change.messageID, forKey: .messageID)
        switch change {
        case .edit(_, let content, let images):
            try container.encode("edit", forKey: .kind)
            try container.encode(content, forKey: .content)
            if !images.isEmpty { try container.encode(images, forKey: .images) }
        case .regenerate:
            try container.encode("regenerate", forKey: .kind)
        case .branch:
            try container.encode("branch", forKey: .kind)
        }
    }
}

/// What a Mac's change did: the chat to show, whether it is a new branch,
/// and whether its last question is now to be answered, which a turn that
/// says `answer_saved` does.
public struct HubChatChanged: Decodable, Sendable, Equatable {
    public let conversationID: Int64
    public let forked: Bool
    public let answer: Bool

    public init(conversationID: Int64, forked: Bool, answer: Bool) {
        self.conversationID = conversationID
        self.forked = forked
        self.answer = answer
    }

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case forked
        case answer
    }
}

/// A branch point as an opened chat says it, read into ``BranchPoint`` and
/// written back from one.
struct HubBranchPointWire: Codable {
    struct Option: Codable {
        let conversationID: Int64
        let messageID: Int64?
        let role: BranchRole?
        let preview: String

        enum CodingKeys: String, CodingKey {
            case conversationID = "conversation_id"
            case messageID = "message_id"
            case role
            case preview
        }
    }

    let messageID: Int64?
    let index: Int
    let options: [Option]

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case index
        case options
    }

    init(_ point: BranchPoint<Int64, Int64>) {
        messageID = point.messageID
        index = point.index
        options = point.options.map {
            Option(conversationID: $0.chatID, messageID: $0.messageID, role: $0.role, preview: $0.preview)
        }
    }

    var point: BranchPoint<Int64, Int64> {
        BranchPoint(
            messageID: messageID, index: index,
            options: options.map {
                BranchOption(chatID: $0.conversationID, messageID: $0.messageID, role: $0.role, preview: $0.preview)
            })
    }
}

extension HubChatOpen {
    /// The row that starts the turn each row is in, by id, as gglib names a
    /// branch point: a question's own, and a reply's first row, which may be
    /// one that only called a tool and is not drawn. A system row starts
    /// none, and a role this build does not know is read as a tool's.
    public var turnStarts: [Int64: Int64] {
        let roles = messages.map { BranchRole(rawValue: $0.role) ?? .tool }
        var starts: [Int64: Int64] = [:]
        for unit in BranchRules.units(roles) {
            for at in unit.rows { starts[messages[at].id] = messages[unit.rows.lowerBound].id }
        }
        return starts
    }
}

extension OpenAICompatibleProvider {
    /// `POST chats/{id}/changes`. A refusal says why in the Mac's own words.
    public func changeChat(id: Int64, change: HubChatChange) async throws(HubChatsFailure) -> HubChatChanged {
        let body: Data
        do {
            body = try JSONEncoder().encode(change)
        } catch {
            throw .refused(.decoding("could not encode the change: \(error)"))
        }
        return try await callHub(HubChatChanged.self, at: "chats/\(id)/changes", method: "POST", body: body)
    }
}
