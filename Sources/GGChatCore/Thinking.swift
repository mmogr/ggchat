// Turning a model's thinking off, for a conversation kept on this device.
// gglib says which of its models think, and takes a thinking budget of zero
// on a request as "do not think". A conversation a Mac keeps says its choice
// another way, with a word on the turn (`HubChatSettings.swift`).

extension ModelInfo {
    /// Whether gglib's model list says this model thinks before it answers:
    /// `reasoning` in its `capabilities`, which gglib writes for a model
    /// tagged that way. Another server never writes it, and neither does a
    /// gglib from before the Thinking switch, so false here says nothing
    /// about a model that is not a current gglib's.
    public var thinks: Bool {
        capabilities?.contains("reasoning") == true
    }
}

extension ChatRequest {
    /// The `reasoningBudgetTokens` that turns thinking off for one request:
    /// gglib's `reasoning_budget_tokens: 0`.
    public static let noThinking = 0
}
