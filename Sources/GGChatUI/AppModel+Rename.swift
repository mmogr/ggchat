import Foundation
import GGChatCore

extension AppModel {
    /// Names a conversation kept here: the list and the chat call it `name`,
    /// trimmed, over the title its first question gives it. An empty name
    /// gives that title back, and one the same as the title already shown
    /// changes nothing, so a name confirmed as it was offered is not kept as
    /// one. Fetched again by id and `updatedAt` left alone, for
    /// `setSystemPrompt`'s reasons: a chat renamed is not moved to the top.
    public func renameConversation(_ id: UUID, to name: String) {
        guard var conversation = conversations.first(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != conversation.displayTitle else { return }
        conversation.title = trimmed
        update(conversation)
    }
}
