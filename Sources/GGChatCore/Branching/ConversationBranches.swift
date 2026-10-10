import Foundation

/// A message as the branch points key it: the message it copies as first
/// written, or its own, with the time it was first written, so the options
/// at a point come oldest first, as gglib orders them. A copy keeps both.
public struct MessageKey: Hashable, Comparable, Sendable {
    public var createdAt: Date
    public var id: UUID

    public init(_ message: Message) {
        createdAt = message.createdAt
        id = message.originID ?? message.id
    }

    public static func < (lhs: MessageKey, rhs: MessageKey) -> Bool {
        (lhs.createdAt, lhs.id) < (rhs.createdAt, rhs.id)
    }
}

/// What a change did to this device's conversations (ADR 0010): the
/// conversation to show, whether it is a new branch, and whether its last
/// question is now to be answered.
public struct ConversationChange: Sendable, Equatable {
    public var conversation: Conversation
    public var isBranch: Bool
    public var answer: Bool
}

extension BranchRole {
    init(_ role: Role) {
        switch role {
        case .system: self = .system
        case .user: self = .user
        case .assistant: self = .assistant
        }
    }
}

extension Conversation {
    /// The messages as the branching rules read them.
    public var branchRows: [BranchRow<UUID>] {
        messages.map {
            BranchRow(id: $0.id, role: BranchRole($0.role), content: $0.content, images: $0.images.map(\.id))
        }
    }

    /// The conversation as the branch points read it.
    public var lineChat: LineChat<UUID, UUID, MessageKey, Date> {
        LineChat(
            chatID: id, updatedAt: updatedAt,
            rows: messages.map {
                LineRow(
                    id: $0.id, key: MessageKey($0), role: BranchRole($0.role), text: $0.content, images: $0.images.count
                )
            })
    }

    /// Makes `change` as the rules say, `busy` saying whether a reply to the
    /// conversation is being written. A question edited in place takes a new
    /// id, so no branch reads it as the question it was; a branch is `newID`,
    /// made at `now`, with a copy of each message as far as the change, then
    /// the message the change adds. An edit carries `images`, and the rules
    /// read their ids from them: the ids an edit names are not read.
    ///
    /// - Throws: ``BranchRefusal``, and nothing is changed.
    public func applying(
        _ change: ChatChange<UUID>, images: [ImageRef] = [], busy: Bool, newID: UUID = UUID(), now: Date
    ) throws(BranchRefusal) -> ConversationChange {
        var change = change
        var content = ""
        if case .edit(let id, let text, _) = change {
            change = .edit(messageID: id, content: text, images: images.map(\.id))
            content = text
        }
        switch try BranchRules.plan(branchRows, change, busy: busy) {
        case .replace(let question):
            var edited = self
            guard let at = messages.firstIndex(where: { $0.id == question }) else { throw .messageNotFound }
            edited.messages[at] = Message(role: .user, content: content, createdAt: now, images: images)
            edited.updatedAt = now
            return ConversationChange(conversation: edited, isBranch: false, answer: true)
        case .fork(let through, let then, let answer):
            let end = through.flatMap { id in messages.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
            var copied = messages[..<end].map(\.copied)
            switch then {
            case .nothing: break
            case .question: copied.append(Message(role: .user, content: content, createdAt: now, images: images))
            case .editedReply: copied.append(Message(role: .assistant, content: content, createdAt: now))
            }
            let branch = Conversation(
                id: newID, title: title, providerID: providerID, model: model, messages: copied,
                systemPrompt: systemPrompt, createdAt: now, updatedAt: now, thinkingOff: thinkingOff,
                branchOf: id, family: familyID)
            return ConversationChange(conversation: branch, isBranch: true, answer: answer)
        }
    }

    /// The branch points the conversation's family, of `conversations`,
    /// holds along it.
    public func branchPoints(among conversations: [Conversation]) -> [BranchPoint<UUID, UUID>] {
        let family = conversations.filter { $0.familyID == familyID }
        guard family.count > 1 else { return [] }
        return BranchRules.points(id, family: family.map(\.lineChat))
    }
}

extension Message {
    /// The text an edit to `text` saves: nil when it would leave the message
    /// blank, unless the message carries images, and the message's own text,
    /// space and all, when it differs from it only by the space around it,
    /// so the rules refuse it as unchanged.
    public func edited(to text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return nil }
        return trimmed == content.trimmingCharacters(in: .whitespacesAndNewlines) ? content : trimmed
    }

    /// A copy for a branch: a new id, remembering the message it copies as
    /// first written. Never a reply being written: a copy carries no run.
    var copied: Message {
        var copy = self
        copy.id = UUID()
        copy.originID = originID ?? id
        copy.runID = nil
        copy.runCursor = nil
        return copy
    }
}
