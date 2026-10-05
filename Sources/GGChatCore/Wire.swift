/// Codable shapes for `/v1/models` and chat completion chunks, with gglib's
/// extras (`description`, `context_window`, `capabilities`) optional so any
/// server decodes. The request is in `ChatCompletionRequest.swift`.
public struct ModelInfo: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var ownedBy: String?
    public var description: String?
    public var contextWindow: Int?
    /// What gglib says the model can do beyond chat, absent for a plain chat
    /// model: `vision` for one that reads images (``readsImages``) and
    /// `reasoning` for one that thinks (``thinks``).
    public var capabilities: [String]?

    public init(
        id: String, ownedBy: String? = nil, description: String? = nil, contextWindow: Int? = nil,
        capabilities: [String]? = nil
    ) {
        self.id = id
        self.ownedBy = ownedBy
        self.description = description
        self.contextWindow = contextWindow
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
        case description
        case contextWindow = "context_window"
        case capabilities
    }
}

struct ModelsResponse: Decodable {
    var data: [ModelInfo]
}

/// What one model call counted. `contextSize` and `trimmedMessages` are
/// gglib's own, sent to a request that asked for progress and on an agent
/// run's `turn_usage`: no other server sends them, and absent means unknown,
/// never zero. Either that does not read costs only itself.
public struct Usage: Codable, Sendable, Equatable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var cachedTokens: Int?
    /// The context the server that answered was started with.
    public var contextSize: Int?
    /// How many earlier messages were shortened or left out so this request
    /// fit.
    public var trimmedMessages: Int?

    public init(
        promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil, cachedTokens: Int? = nil,
        contextSize: Int? = nil, trimmedMessages: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
        self.contextSize = contextSize
        self.trimmedMessages = trimmedMessages
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case contextSize = "context_size"
        case trimmedMessages = "trimmed_messages"
    }

    struct Details: Codable {
        var cachedTokens: Int?
        enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens" }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens)
        completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        cachedTokens = try container.decodeIfPresent(Details.self, forKey: .promptTokensDetails)?.cachedTokens
        contextSize = try? container.decodeIfPresent(Int.self, forKey: .contextSize)
        trimmedMessages = try? container.decodeIfPresent(Int.self, forKey: .trimmedMessages)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try container.encodeIfPresent(completionTokens, forKey: .completionTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
        if let cachedTokens {
            try container.encode(Details(cachedTokens: cachedTokens), forKey: .promptTokensDetails)
        }
        try container.encodeIfPresent(contextSize, forKey: .contextSize)
        try container.encodeIfPresent(trimmedMessages, forKey: .trimmedMessages)
    }
}

/// A streamed chunk. When the request asks for them, gglib's first chunks
/// carry `prompt_progress` and no `choices` key at all; the usage chunk has
/// `choices: []`. Both decode.
///
/// `error` is the other thing a chunk can be: a failure written into a stream
/// that had already begun. gglib writes it bare, an `error` object and no
/// `choices` key, so that clients tell it from a chunk by that shape. This
/// reads a wire it does not own, so an `error` member ends the reply whether
/// or not `choices` sits beside it.
///
/// A `prompt_progress` that does not read is dropped and the rest of the
/// chunk is read as before, so a chunk that decoded without it still does.
struct ChatCompletionChunk: Decodable {
    var choices: [Choice]?
    var usage: Usage?
    var error: StreamError?
    var promptProgress: PromptProgress?

    enum CodingKeys: String, CodingKey {
        case choices, usage, error
        case promptProgress = "prompt_progress"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices)
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        error = try container.decodeIfPresent(StreamError.self, forKey: .error)
        promptProgress = try? container.decodeIfPresent(PromptProgress.self, forKey: .promptProgress)
    }

    /// The `error` member, as an object with a message and a code, or as a
    /// bare string, which llama.cpp has been seen to send and gglib accepts
    /// (`gglib-core/src/sse/parser.rs`, `parse_inline_error_frame`). A code
    /// may be a number, as in `APIErrorBody`.
    struct StreamError: Decodable, Equatable {
        var message: String
        var code: String?

        enum CodingKeys: String, CodingKey { case message, code }

        init(message: String, code: String?) {
            self.message = message
            self.code = code
        }

        init(from decoder: any Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                message = text
                code = nil
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message =
                (try? container.decodeIfPresent(String.self, forKey: .message))
                ?? "the server reported an error part-way through the reply"
            if let text = try? container.decodeIfPresent(String.self, forKey: .code) {
                code = text
            } else if let number = try? container.decodeIfPresent(Int.self, forKey: .code) {
                code = String(number)
            } else {
                code = nil
            }
        }
    }

    struct Choice: Decodable {
        var delta: Delta?
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        var content: String?
        var reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
}

/// How much of the prompt the server has read, from gglib's
/// `prompt_progress`: `processed` of `total` tokens, `cache` of them from its
/// cache, in `timeMs` so far. It is shown while a reply waits and never kept.
public struct PromptProgress: Decodable, Sendable, Equatable {
    public var processed: Int
    public var total: Int
    public var cache: Int?
    public var timeMs: Int?

    public init(processed: Int, total: Int, cache: Int? = nil, timeMs: Int? = nil) {
        self.processed = processed
        self.total = total
        self.cache = cache
        self.timeMs = timeMs
    }

    enum CodingKeys: String, CodingKey {
        case processed, total, cache
        case timeMs = "time_ms"
    }
}

/// `{"error":{"message":…,"type":…,"code":…}}`. Some servers send `code` as a
/// number; it is kept as text either way.
public struct APIErrorBody: Decodable, Sendable, Equatable {
    public var error: APIError

    public struct APIError: Decodable, Sendable, Equatable {
        public var message: String
        public var type: String?
        public var code: String?

        enum CodingKeys: String, CodingKey { case message, type, code }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            if let text = try? container.decodeIfPresent(String.self, forKey: .code) {
                code = text
            } else if let number = try? container.decodeIfPresent(Int.self, forKey: .code) {
                code = String(number)
            } else {
                code = nil
            }
        }
    }
}
