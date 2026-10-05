import GGChatCore

// The reading the context ring draws, for each kind of chat. The counts are
// gglib's: where it reported no context size there is no reading and no
// ring, and nothing here estimates one (ADR 0008).
extension AppModel {
    /// The reading to draw for a conversation kept here: the one its last
    /// finished reply left, while the model a send would use now is the
    /// model that reply was asked of. Under another model it says nothing
    /// about what the next request will find, so it is not drawn; back on
    /// the same model it is drawn again.
    public func contextReading(for conversation: Conversation) -> ContextReading? {
        guard let reading = conversation.context,
            reading.model == (conversation.model ?? provider(for: conversation)?.defaultModel)
        else { return nil }
        return reading
    }

    /// The reading to draw for the Mac's chat open: what the reply in hand
    /// last counted once it has counted anything, and until then what the
    /// rows last read say. None while the chat says why it has no rows, so no
    /// ring stands over that sentence. Held in memory with the chat and the
    /// reply, and never written to this phone (ADR 0007).
    public var hubContextReading: ContextReading? {
        guard let open = openedHubChat else { return nil }
        if case .unavailable = open.state { return nil }
        if let reply = openHubReply, let usage = reply.usage {
            return ContextReading(usage, reason: reply.finishReason)
        }
        return open.context
    }
}
