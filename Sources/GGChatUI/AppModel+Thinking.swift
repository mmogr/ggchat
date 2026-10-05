import Foundation
import GGChatCore

// The Thinking switch, for each kind of chat (ADR 0009). It is offered only
// where gglib's model list says the model thinks. A conversation kept here
// stores the choice and sends it with every request. A Mac's chat is the
// Mac's to remember: the choice goes with the turn that changes it, and
// nothing of it is written to this phone (ADR 0007).

/// What this phone holds of the Thinking choice of the Mac's chat open: in
/// memory with the chat, and gone with it.
struct HubChatThinking: Equatable, Sendable {
    /// Whether the Mac remembers the chat's thinking switched off: what it
    /// said when the chat was last read, or the last turn it took said.
    var rememberedOff = false
    /// What the switch was set to here, until the Mac is known to remember
    /// the same; nil otherwise, and the switch then shows what the Mac
    /// remembers.
    var chosenOff: Bool?
    /// The model the chat last ran on, as its settings or else its last
    /// reply name it.
    var modelName: String?

    /// Whether the switch shows off.
    var isOff: Bool {
        chosenOff ?? rememberedOff
    }

    /// What the next turn says of the choice: the word for it while it
    /// differs from what the Mac remembers, and nothing otherwise.
    var change: HubThinking? {
        guard let chosenOff, chosenOff != rememberedOff else { return nil }
        return chosenOff ? .off : .default
    }

    /// The Mac now remembers `off`: a turn it took said so, or the chat read
    /// again does. The switch stays as it was set here unless that is what
    /// the Mac remembers, and from then on it shows what the Mac does.
    mutating func remember(off: Bool) {
        rememberedOff = off
        if chosenOff == off { chosenOff = nil }
    }

    /// Takes what an opened chat says: what the Mac remembers, and its
    /// model, which its settings name or else its last reply that names one.
    mutating func read(_ chat: HubChatOpen) {
        remember(off: chat.conversation.settings?.thinking == .off)
        let named = chat.messages.last { $0.role == Role.assistant.rawValue && $0.metadata?.modelName != nil }
        modelName = chat.conversation.settings?.modelName ?? named?.metadata?.modelName
    }
}

extension AppModel {
    // MARK: - A conversation kept here

    /// Whether a provider's model list says a model thinks, or nil when the
    /// list does not name it or has not been read.
    func listsAsThinking(_ modelID: String?, on providerID: UUID?) -> Bool? {
        guard let modelID, let providerID else { return nil }
        return models(for: providerID).first { $0.id == modelID }?.thinks
    }

    /// Whether the conversation is offered the switch: its provider is gglib
    /// (`asksForProgress`) and gglib's list names its model as one that
    /// thinks. Another server, a model the list does not name and a list not
    /// read yet all offer none.
    public func offersThinking(for conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation), asksForProgress(config) else { return false }
        return listsAsThinking(conversation.model ?? config.defaultModel, on: config.id) == true
    }

    /// Sets whether the model is asked not to think in this conversation,
    /// from its next request on. Fetched again by id and `updatedAt` left
    /// alone, for `setSystemPrompt`'s reasons.
    public func setThinking(off: Bool, for conversationID: UUID) {
        guard var conversation = conversations.first(where: { $0.id == conversationID }),
            conversation.thinkingOff != off
        else { return }
        conversation.thinkingOff = off
        update(conversation)
    }

    /// Whether the conversation's switch shows on, which is while it is not
    /// switched off. The view is handed this as it is, so the opposite is
    /// taken here, where a test reads it.
    public func thinkingOn(for conversation: Conversation) -> Bool {
        !conversation.thinkingOff
    }

    /// Sets the conversation's switch to what a press says: on asks the
    /// model to think again, and off asks it not to.
    public func setThinking(on: Bool, for conversationID: UUID) {
        setThinking(off: !on, for: conversationID)
    }

    /// The thinking budget a request carries: none for a conversation
    /// switched off, and nothing said otherwise, which leaves the key out.
    /// Only gglib is sent it, and not for a model its list names as one that
    /// does not think.
    func thinkingBudget(off: Bool, model: String, for config: ProviderConfig) -> Int? {
        guard off, asksForProgress(config), listsAsThinking(model, on: config.id) != false else { return nil }
        return ChatRequest.noThinking
    }

    // MARK: - A Mac's chat

    /// The model the Mac's chat open runs on, as that Mac's list has it: the
    /// name its settings give, else its last reply's, else the one the list
    /// of chats gives it. Nil when it names none, or one the Mac does not
    /// list now.
    func hubChatModel(_ open: OpenHubChat) -> ModelInfo? {
        let name = open.thinking.modelName ?? hubChats[open.providerID]?.first { $0.id == open.chatID }?.model
        guard let name else { return nil }
        return models(for: open.providerID).first { $0.id == name }
    }

    /// Whether the chat open is offered the switch: its rows are read, so
    /// what the Mac remembers is known, and the Mac lists its model as one
    /// that thinks.
    public var hubChatOffersThinking: Bool {
        guard let open = openedHubChat, open.state.showsRows else { return false }
        return hubChatModel(open)?.thinks == true
    }

    /// Whether the chat open has its thinking switched off: what the Mac
    /// remembers, until the switch is set here.
    public var hubThinkingOff: Bool {
        openedHubChat?.thinking.isOff ?? false
    }

    /// Sets the switch of the chat open. It is said to the Mac with the next
    /// turn, and until then it is held with the chat and nowhere else.
    public func setHubThinking(off: Bool) {
        openedHubChat?.thinking.chosenOff = off
    }

    /// Whether the switch of the chat open shows on: the opposite of
    /// `hubThinkingOff`, taken here and not in the view.
    public var hubThinkingOn: Bool {
        !hubThinkingOff
    }

    /// Sets the switch of the chat open to what a press says.
    public func setHubThinking(on: Bool) {
        setHubThinking(off: !on)
    }

    /// The Mac took a turn: what the turn said of the choice is what the Mac
    /// now remembers, so the turns after it say nothing.
    func hubTookTurn(_ reply: HubLiveReply) {
        guard let said = reply.thinking, openedHubChat?.providerID == reply.providerID,
            openedHubChat?.chatID == reply.chatID
        else { return }
        openedHubChat?.thinking.remember(off: said == .off)
    }
}
