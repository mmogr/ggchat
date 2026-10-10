import Foundation
import GGChatCore

/// Edit, regenerate and Branch from here on this device's conversations
/// (ADR 0010). A change that would discard or alter a saved reply is made on
/// a new branch of the conversation, which opens; the conversation it was
/// made on is left as it was. The rules are ``BranchRules``'; nothing here
/// decides when a change branches.
extension AppModel {
    /// The branch points the conversation's family holds along it: where
    /// another of its conversations goes on differently.
    public func branchPoints(of conversation: Conversation) -> [BranchPoint<UUID, UUID>] {
        conversation.branchPoints(among: conversations)
    }

    /// Asks a question again in other words, keeping its images, or keeps a
    /// reply as written. A question is answered again; an edited reply is
    /// not. Blank text changes nothing, and neither does text that differs
    /// from the message only by the space around it.
    @discardableResult
    public func edit(_ messageID: UUID, in conversationID: UUID, to text: String) -> Task<Void, Never>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let conversation = conversation(conversationID),
            let message = conversation.messages.first(where: { $0.id == messageID }),
            !trimmed.isEmpty || !message.images.isEmpty
        else { return nil }
        // A reply is saved as it streamed, space and all.
        let same = trimmed == message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = same ? message.content : trimmed
        let images = message.role == .user ? message.images : []
        return make(.edit(messageID: messageID, content: content, images: []), images: images, in: conversation)
    }

    /// Answers again the question a reply answers, on a new branch.
    @discardableResult
    public func regenerate(_ messageID: UUID, in conversationID: UUID) -> Task<Void, Never>? {
        guard let conversation = conversation(conversationID) else { return nil }
        return make(.regenerate(messageID: messageID), in: conversation)
    }

    /// Copies the conversation, as far as the end of the turn holding the
    /// message, into a new branch to go on in. Nothing is sent.
    public func branch(from messageID: UUID, in conversationID: UUID) {
        guard let conversation = conversation(conversationID) else { return }
        make(.branch(messageID: messageID), in: conversation)
    }

    /// What a turn's menu offers on the conversation, `edit` opening the
    /// editor on the turn.
    func messageChanges(in conversationID: UUID, edit: @escaping (Message) -> Void) -> MessageChanges {
        MessageChanges(
            edit: edit, regenerate: { [weak self] in self?.regenerate($0, in: conversationID) },
            branch: { [weak self] in self?.branch(from: $0, in: conversationID) })
    }

    /// Opens a conversation of the family: an option at a branch point.
    public func openBranch(_ conversationID: UUID) {
        guard conversation(conversationID) != nil else { return }
        selection = .local(conversationID)
    }

    private func conversation(_ id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Makes the change, then answers the question it leaves when it says
    /// to and the conversation can take a turn now. A branch whose answer
    /// cannot start is opened unanswered, and Retry answers it.
    @discardableResult
    private func make(
        _ change: ChatChange<UUID>, images: [ImageRef] = [], in conversation: Conversation
    ) -> Task<Void, Never>? {
        let busy = isStreaming(conversation.id) || conversation.messages.contains(where: \.isBeingWritten)
        let made: ConversationChange
        do {
            made = try conversation.applying(change, images: images, busy: busy, now: now())
        } catch {
            lastError = Self.sentence(for: error)
            return nil
        }
        if made.isBranch {
            add(branch: made.conversation)
        } else {
            update(made.conversation)
        }
        guard made.answer, takesTurn(made.conversation) else { return nil }
        return stream(made.conversation, continuing: nil)
    }

    /// Why a change was not made, for the window to say, or nil for an edit
    /// that changes nothing, which needs no sentence.
    static func sentence(for refusal: BranchRefusal) -> String? {
        switch refusal {
        case .unchanged: nil
        case .messageNotFound: "That message is no longer in this conversation."
        case .notAReply: "Only a reply can be answered again."
        case .nothingToAnswer: "There is no question here to answer."
        case .imagesOnReply: "A reply cannot carry images."
        }
    }
}
