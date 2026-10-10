import Foundation

/// The body of `chat/completions`, and of a run's `PUT`, which takes the same
/// one.
struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [WireMessage]
    var stream = true
    var streamOptions = StreamOptions()
    var maxTokens: Int?
    /// `true` when asked and absent otherwise, so a server that is not gglib
    /// never sees the key.
    var returnProgress: Bool?
    /// gglib's thinking budget, `0` for none, and absent unless the request
    /// sets one, so the body is what it always was.
    var reasoningBudgetTokens: Int?

    struct WireMessage: Encodable {
        var role: String
        var content: Content
    }

    /// A turn's content, as the OpenAI wire has it: the text alone for a
    /// turn with no images, the same bare string it always was, and a list
    /// of parts for one with images, the text first.
    enum Content: Encodable, Equatable {
        case text(String)
        case parts([Part])

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    /// `{"type":"text","text":…}`, or `{"type":"image_url","image_url":{"url":…}}`
    /// with the image in a `data:` URL.
    enum Part: Encodable, Equatable {
        case text(String)
        case imageURL(String)

        private enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        private struct ImageURL: Encodable {
            var url: String
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURL(url: url), forKey: .imageURL)
            }
        }
    }

    struct StreamOptions: Encodable {
        var includeUsage = true
        enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
        case maxTokens = "max_tokens"
        case returnProgress = "return_progress"
        case reasoningBudgetTokens = "reasoning_budget_tokens"
    }

    /// Throws ``MissingImage`` when a message names an image whose bytes the
    /// request does not hold, rather than sending the turn without it.
    init(_ request: ChatRequest) throws(MissingImage) {
        model = request.model
        messages = try request.messages.map { message throws(MissingImage) in
            WireMessage(role: message.role.rawValue, content: try Self.content(of: message, images: request.images))
        }
        maxTokens = request.maxTokens
        returnProgress = request.returnProgress ? true : nil
        reasoningBudgetTokens = request.reasoningBudgetTokens
    }

    /// A reply's images are ones a tool made for the person to look at.
    /// They are never sent back to the model: a reply is its text alone.
    private static func content(of message: Message, images: [String: Data]) throws(MissingImage) -> Content {
        guard !message.images.isEmpty, message.role != .assistant else { return .text(message.content) }
        let text: [Part] = message.content.isEmpty ? [] : [.text(message.content)]
        let pictures = try message.images.map { image throws(MissingImage) -> Part in
            guard let data = images[image.id] else { throw MissingImage(id: image.id) }
            return .imageURL("data:\(image.mime);base64,\(data.base64EncodedString())")
        }
        return .parts(text + pictures)
    }

    /// A message names an image the request holds no bytes for. It says the
    /// id and nothing of any image, so it can go in an error's sentence.
    struct MissingImage: Error, CustomStringConvertible {
        var id: String
        var description: String { "an image the request names has no bytes (\(id))" }
    }
}
