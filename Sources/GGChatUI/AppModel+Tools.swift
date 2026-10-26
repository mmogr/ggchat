import Foundation
import GGChatCore

// The Tools switch of a conversation kept here. It is offered only where the
// paired Mac said it offers MCP servers' tools, and it is on until it is
// turned off. Which servers the Mac offers is chosen on the Mac and only
// read here.
extension AppModel {
    /// Whether the conversation is offered the switch: its provider is a
    /// paired Mac whose answer about drawing named servers it offers
    /// (`offersTools`). A gglib reached by address, a Mac that names none,
    /// one from before the list and one not heard from all offer none.
    public func offersTools(for conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation) else { return false }
        return offersTools(config)
    }

    /// The servers a paired Mac offers its runs, by id and name, in its
    /// order, for the server-status sheet to list: none where no tools are
    /// offered (`offersTools`).
    public func toolsOffered(by config: ProviderConfig) -> [OfferedServer] {
        offersTools(config) ? drawings[config.id]?.mcpServers ?? [] : []
    }

    /// Whether the conversation's switch shows on, which is while it is not
    /// switched off. The opposite is taken here, where a test reads it.
    public func toolsOn(for conversation: Conversation) -> Bool {
        !conversation.toolsOff
    }

    /// Sets whether the conversation's questions may call the Mac's tools,
    /// from its next request on. Fetched again by id and `updatedAt` left
    /// alone, for `setSystemPrompt`'s reasons.
    public func setTools(on: Bool, for conversationID: UUID) {
        let off = !on
        guard var conversation = conversations.first(where: { $0.id == conversationID }),
            conversation.toolsOff != off
        else { return }
        conversation.toolsOff = off
        update(conversation)
    }
}
