import Foundation

/// Codable shapes for `/v1/models` and chat completion chunks, with gglib's
/// extras (`description`, `context_window`) optional so any server decodes.
public struct ModelInfo: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var ownedBy: String?
    public var description: String?
    public var contextWindow: Int?

    public init(id: String, ownedBy: String? = nil, description: String? = nil, contextWindow: Int? = nil) {
        self.id = id
        self.ownedBy = ownedBy
        self.description = description
        self.contextWindow = contextWindow
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
        case description
        case contextWindow = "context_window"
    }
}

struct ModelsResponse: Decodable {
    var data: [ModelInfo]
}

public struct Usage: Codable, Sendable, Equatable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var cachedTokens: Int?

    public init(
        promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil, cachedTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cachedTokens = cachedTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
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
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try container.encodeIfPresent(completionTokens, forKey: .completionTokens)
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
        if let cachedTokens {
            try container.encode(Details(cachedTokens: cachedTokens), forKey: .promptTokensDetails)
        }
    }
}

/// A streamed chunk. gglib's first chunks carry `prompt_progress` and no
/// `choices` key at all; the usage chunk has `choices: []`. Both decode.
struct ChatCompletionChunk: Decodable {
    var choices: [Choice]?
    var usage: Usage?

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

struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [WireMessage]
    var stream = true
    var streamOptions = StreamOptions()
    var maxTokens: Int?

    struct WireMessage: Encodable {
        var role: String
        var content: String
    }

    struct StreamOptions: Encodable {
        var includeUsage = true
        enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
        case maxTokens = "max_tokens"
    }

    init(_ request: ChatRequest) {
        model = request.model
        messages = request.messages.map { WireMessage(role: $0.role.rawValue, content: $0.content) }
        maxTokens = request.maxTokens
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
