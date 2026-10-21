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

    /// One message. A turn is its role and content, as it always was. A
    /// tool a reply called is two more: an assistant message with no
    /// content and the call in `tool_calls`, then a `tool` message with the
    /// call's id and the tool's answer. A key with nothing to say is left
    /// out, as gglib leaves it out of the history it writes itself.
    struct WireMessage: Encodable {
        var role: String
        var content: Content?
        var toolCalls: [WireToolCall]?
        var toolCallID: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }
    }

    /// `{"id":…,"type":"function","function":{"name":…,"arguments":…}}`,
    /// the arguments a string of JSON, as OpenAI writes them.
    struct WireToolCall: Encodable {
        struct Function: Encodable {
            var name: String
            var arguments: String
        }

        var id: String
        var type = "function"
        var function: Function
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
        var wire: [WireMessage] = []
        for (index, message) in request.messages.enumerated() {
            let calls = request.replaysToolCalls ? Self.toolMessages(of: message) : []
            wire += calls
            // A reply of a picture alone has no words to send after it.
            if !calls.isEmpty, message.content.isEmpty { continue }
            let shown = request.shownPicture.flatMap { $0.at == index ? $0.image : nil }
            wire.append(
                WireMessage(
                    role: message.role.rawValue,
                    content: try Self.content(of: message, showing: shown, images: request.images)))
        }
        messages = wire
        maxTokens = request.maxTokens
        returnProgress = request.returnProgress ? true : nil
        reasoningBudgetTokens = request.reasoningBudgetTokens
    }

    /// What goes ahead of a reply's words for the tools it called: for each
    /// one that answered, in order, the call and then its answer. A call
    /// with no answer is left out, since a history may not hold a call
    /// nothing answers. Each call is a message of its own, so the answer
    /// always follows the call it answers.
    private static func toolMessages(of message: Message) -> [WireMessage] {
        guard message.role == .assistant else { return [] }
        return message.exchanges.flatMap { exchange -> [WireMessage] in
            guard let result = exchange.result else { return [] }
            let call = WireToolCall(
                id: exchange.callID, function: .init(name: exchange.name, arguments: exchange.arguments))
            return [
                WireMessage(role: Role.assistant.rawValue, toolCalls: [call]),
                WireMessage(role: "tool", content: .text(result), toolCallID: exchange.callID),
            ]
        }
    }

    /// A reply's images are ones a tool made for the person to look at.
    /// They are not sent back as the reply's: a reply is its text alone.
    /// The drawn picture a request shows (`shown`) goes on the message
    /// after it instead, as ``ShownPicture/line`` and the picture ahead of
    /// the message's own parts.
    private static func content(
        of message: Message, showing shown: ImageRef?, images: [String: Data]
    ) throws(MissingImage) -> Content {
        let own = message.role == .assistant ? [] : message.images
        guard !own.isEmpty || shown != nil else { return .text(message.content) }
        var added: [Part] = []
        if let shown { added = [.text(ShownPicture.line), try part(of: shown, images: images)] }
        let text: [Part] = message.content.isEmpty ? [] : [.text(message.content)]
        let pictures = try own.map { image throws(MissingImage) in try part(of: image, images: images) }
        return .parts(added + text + pictures)
    }

    /// An image as an `image_url` part, its bytes in a `data:` URL.
    private static func part(of image: ImageRef, images: [String: Data]) throws(MissingImage) -> Part {
        guard let data = images[image.id] else { throw MissingImage(id: image.id) }
        return .imageURL("data:\(image.mime);base64,\(data.base64EncodedString())")
    }

    /// A message names an image the request holds no bytes for. It says the
    /// id and nothing of any image, so it can go in an error's sentence.
    struct MissingImage: Error, CustomStringConvertible {
        var id: String
        var description: String { "an image the request names has no bytes (\(id))" }
    }
}
