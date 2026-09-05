/// What the app sends. Messages are the conversation so far, in order.
public struct ChatRequest: Sendable, Equatable {
    public var model: String
    public var messages: [Message]
    public var maxTokens: Int?

    public init(model: String, messages: [Message], maxTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
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
