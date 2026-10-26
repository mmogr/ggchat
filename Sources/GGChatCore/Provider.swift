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
    /// How many tokens the model may spend thinking, or nil to say nothing:
    /// ``noThinking`` turns thinking off for this request. Set only for
    /// gglib, as `returnProgress` is.
    public var reasoningBudgetTokens: Int?
    /// Whether the message was sent with Draw pressed, so its reply may ask
    /// gglib for a picture. No part of the body: a run's `PUT` says it in
    /// its query, and the chat route, which cannot draw, never hears it.
    /// Set only for a gglib that said it can draw.
    public var draws: Bool
    /// The image model the picture is drawn with, by its id on the hub, or
    /// nil for the one the hub's own rule picks. No part of the body
    /// either: a run that draws says it in its query, beside `draw`, and
    /// one that does not draw never says it. Set only for a gglib whose
    /// answer about drawing listed its image models.
    public var imageModelID: UInt64?
    /// The MCP servers whose tools the run may call, by their ids on the
    /// paired Mac, sorted: no part of the body, as `draws` is not. A run
    /// that names any, or draws, is put with gglib's tools (`tools=` in its
    /// query, `toolsWord`); one that does neither is a plain run. Set only
    /// for a paired Mac, which drops any it does not open to devices.
    public var toolServers: [Int64]
    /// Whether a reply is sent with the tools it called and what they
    /// answered (``Message/exchanges``), as an assistant message with
    /// `tool_calls` and a `tool` message ahead of its words. Set only for
    /// gglib, which reads them: another server may refuse a tool message
    /// in a request that offers no tools, and is sent the reply's words
    /// alone, as before.
    public var replaysToolCalls: Bool
    /// The drawn picture shown to the model, on the message it names, with
    /// its bytes in `images`. Set only for gglib, and only for a model its
    /// list names as one that reads images: gglib refuses an image to any
    /// other.
    public var shownPicture: ShownPicture?

    public init(
        model: String, messages: [Message], images: [String: Data] = [:], maxTokens: Int? = nil,
        returnProgress: Bool = false, reasoningBudgetTokens: Int? = nil, draws: Bool = false,
        imageModelID: UInt64? = nil, replaysToolCalls: Bool = false, shownPicture: ShownPicture? = nil,
        toolServers: [Int64] = []
    ) {
        self.model = model
        self.messages = messages
        self.images = images
        self.maxTokens = maxTokens
        self.returnProgress = returnProgress
        self.reasoningBudgetTokens = reasoningBudgetTokens
        self.draws = draws
        self.imageModelID = imageModelID
        self.replaysToolCalls = replaysToolCalls
        self.shownPicture = shownPicture
        self.toolServers = toolServers
    }

    /// Whether the run is put as gglib's agent loop: it draws, or names a
    /// server whose tools it may call. Any other is a plain run.
    public var runsAgentLoop: Bool {
        draws || !toolServers.isEmpty
    }

    /// The run's `tools=` word: `none` for no server, which leaves a run
    /// that draws the drawing tool alone, or the servers' ids in canonical
    /// decimal, sorted, each once, joined by commas.
    public var toolsWord: String {
        toolServers.isEmpty ? "none" : Set(toolServers).sorted().map(String.init).joined(separator: ",")
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
