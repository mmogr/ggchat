import Foundation

/// What the app sends. Messages are the conversation so far, in order.
/// `images` holds the bytes of every image they name, by ``ImageRef/id``: a
/// message carries only references, and the request is where they are read.
public struct ChatRequest: Sendable, Equatable {
    public var model: String
    public var messages: [Message]
    public var images: [String: Data]
    public var maxTokens: Int?
    /// Whether to ask for gglib's progress frames while it reads the prompt.
    /// Set only for gglib: another server may refuse a field it does not know.
    public var returnProgress: Bool

    public init(
        model: String, messages: [Message], images: [String: Data] = [:], maxTokens: Int? = nil,
        returnProgress: Bool = false
    ) {
        self.model = model
        self.messages = messages
        self.images = images
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
