import Foundation
import GGChatCore

extension AppModel {
    /// Sets the prompt sent ahead of every request in this conversation, as
    /// `Conversation.systemPrompt` describes. Trimmed, and nil when nothing
    /// is left, so a blank prompt sends no turn at all.
    ///
    /// The conversation is fetched again by id rather than taken from the
    /// caller: the sheet that edits the prompt holds a copy from when it
    /// opened, and a reply that finished while it was open would be lost if
    /// that copy were saved over it. `updatedAt` is left alone, because a
    /// setting changed is not a conversation moved to the top of the list.
    public func setSystemPrompt(_ text: String, for conversationID: UUID) {
        guard var conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.systemPrompt = trimmed.isEmpty ? nil : trimmed
        update(conversation)
    }
}
