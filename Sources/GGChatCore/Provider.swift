/// What the app sends. Messages are the conversation so far, in order.
public struct ChatRequest: Sendable, Equatable {
    public var model: String
    public var messages: [Message]
    public var maxTokens: Int?
    /// Whether to ask for gglib's progress frames while it reads the prompt.
    /// Set only for gglib: another server may refuse a field it does not know.
    public var returnProgress: Bool

    public init(model: String, messages: [Message], maxTokens: Int? = nil, returnProgress: Bool = false) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.returnProgress = returnProgress
    }
}

/// One protocol, one real implementation (`OpenAICompatibleProvider`), one
/// mock. A pipe is not a second implementation: it is a provider whose base
/// URL was minted on the device.
public protocol Provider: Sendable {
    func models() async throws -> [ModelInfo]
    /// Never throws; failures arrive as a terminal `.error` event. Cancelling
    /// the consuming task ends the stream without a terminal event.
    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent>
}
