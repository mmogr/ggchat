import Foundation
import GGChatCore

// Which of the paired Mac's MCP servers a conversation kept here uses. The
// wrench is offered only where the Mac said it offers servers' tools; it is
// a master switch, on for a new conversation, and a pick for each server
// the Mac offers, none picked until one is. The Mac chooses which servers it
// offers; a conversation only picks among them. The wrench is badged while
// the Mac offers a server the conversation has never shown; a change made
// from its menu, or its rows coming on screen in the Duo's panel, shows
// them all.
extension AppModel {
    /// Whether the conversation is offered the wrench: its provider is a
    /// paired Mac whose answer about drawing named servers it offers
    /// (`offersTools`). A gglib reached by address, a Mac that names none,
    /// one from before the list and one not heard from all offer none.
    public func offersTools(for conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation) else { return false }
        return offersTools(config)
    }

    /// The servers a paired Mac offers its runs, by id and name, in its
    /// order, for the server-status sheet and the wrench to list: none where
    /// no tools are offered (`offersTools`).
    public func toolsOffered(by config: ProviderConfig) -> [OfferedServer] {
        offersTools(config) ? drawings[config.id]?.mcpServers ?? [] : []
    }

    /// What the conversation's wrench shows: hidden where no tools are
    /// offered, else its master switch and a row for each server offered.
    public func toolsMenu(for conversation: Conversation) -> ToolsMenu {
        guard let config = provider(for: conversation), offersTools(config) else { return .hidden }
        return ToolsMenu(choice: conversation.toolChoice, offered: toolsOffered(by: config))
    }

    /// Turns the conversation's tools on or off, from its next request on,
    /// keeping what it picked. Made from the menu, it shows every server
    /// offered, as the menu did.
    public func setTools(on: Bool, for conversationID: UUID) {
        changeToolChoice(of: conversationID) { $0.turned(on: on) }
    }

    /// Picks `server`, by its id on the Mac, for the conversation's next
    /// requests, or drops it, and shows every server offered.
    public func setServer(_ server: Int64, picked: Bool, for conversationID: UUID) {
        changeToolChoice(of: conversationID) { $0.picking(server, picked) }
    }

    /// Marks every server the Mac offers as shown in the conversation,
    /// which clears its badge. Once: shown again, nothing is written.
    public func markToolsSeen(for conversationID: UUID) {
        changeToolChoice(of: conversationID, seeing: true) { $0 }
    }

    /// Writes the conversation's choice as `change` leaves it, fetched again
    /// by id and with `updatedAt` left alone, for `setSystemPrompt`'s
    /// reasons. A change made from the menu shows every server offered,
    /// since the menu showed them, in the same write; so does `seeing`. A
    /// change that leaves the choice as it was writes nothing.
    private func changeToolChoice(of conversationID: UUID, seeing: Bool = false, _ change: (ToolChoice) -> ToolChoice) {
        guard var conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        var changed = change(conversation.toolChoice)
        if seeing || changed != conversation.toolChoice, let config = provider(for: conversation) {
            changed = changed.seeing(toolsOffered(by: config).map(\.id))
        }
        guard changed != conversation.toolChoice else { return }
        conversation.toolChoice = changed
        update(conversation)
    }
}
