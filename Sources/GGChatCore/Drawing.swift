import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// Drawing: gglib makes a picture on the machine it runs on, with an image
// model, when a message asks for one. Whether a hub can, what gglib's model
// list says of a model that draws, and the sentences for the ways drawing is
// refused.

/// Whether a message sent with Draw pressed can be drawn on a hub now, as
/// gglib's `GET /v1/images/drawing` answers it (`DrawingAvailability` there):
/// the image model that would draw when it can, and when it cannot, why, in
/// words that say what would fix it. A paired Mac's answer also names the
/// MCP servers whose tools a run from this device is offered.
public struct Drawing: Decodable, Sendable, Equatable {
    public var available: Bool
    /// Why not, as a code: `drawing_unavailable`, or one of the three a
    /// named image model is refused with.
    public var code: String?
    /// Why not, in gglib's words.
    public var reason: String?
    /// The image model that would draw.
    public var model: String?
    /// That model's id on the hub.
    public var modelID: UInt64?
    /// The hub's image models, in the order it gave them. Nil from a gglib
    /// from before the list, which is never sent `image_model`; empty from
    /// one that has the list and no image model.
    public var models: [ImageModelRow]?
    /// The MCP servers whose tools a run from this device is offered, by
    /// name. Nil from a gglib from before the list, and empty from one that
    /// opens none; either way no run is put with tools for them. Said
    /// whether or not the hub can draw: a Mac with no image model can still
    /// offer its servers.
    public var mcpServers: [String]?

    public init(
        available: Bool, code: String? = nil, reason: String? = nil, model: String? = nil, modelID: UInt64? = nil,
        models: [ImageModelRow]? = nil, mcpServers: [String]? = nil
    ) {
        self.available = available
        self.code = code
        self.reason = reason
        self.model = model
        self.modelID = modelID
        self.models = models
        self.mcpServers = mcpServers
    }

    /// Whether a run from this device is offered the tools of at least one
    /// MCP server: absent, `null` and `[]` all mean none.
    public var offersTools: Bool {
        !(mcpServers ?? []).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case available, code, reason, model, models
        case modelID = "model_id"
        case mcpServers = "mcp_servers"
    }
}

/// A provider whose hub can be asked whether it draws.
public protocol DrawingProvider: Provider {
    /// Whether the hub can draw for a message now: one that names
    /// `imageModel`, or with nil one that names none. A hub from before
    /// drawing has no such route, and cannot.
    func drawing(judging imageModel: UInt64?) async throws(ProviderError) -> Drawing
}

extension DrawingProvider {
    /// Whether the hub can draw for a message that names no image model.
    public func drawing() async throws(ProviderError) -> Drawing {
        try await drawing(judging: nil)
    }
}

extension OpenAICompatibleProvider: DrawingProvider {
    /// `GET images/drawing`. A 404 is a gglib from before drawing, which
    /// cannot draw and would refuse a turn's `draw` as a key it does not
    /// know, so it is never sent one.
    ///
    /// With `imageModel` it is `GET images/drawing?image_model=<id>`: the
    /// same question about a message that names that model, which gglib
    /// judges as it would the message. The answer is then about that model
    /// alone, and says `model_not_found`, `not_an_image_model` or
    /// `image_model_incomplete` when that is why not.
    public func drawing(judging imageModel: UInt64?) async throws(ProviderError) -> Drawing {
        var request = makeRequest(path: "images/drawing", method: "GET", body: nil)
        if let imageModel {
            request.url = request.url?.appending(queryItems: [
                URLQueryItem(name: "image_model", value: String(imageModel))
            ])
        }
        let (data, response) = try await perform(request)
        if response.statusCode == 404 { return Drawing(available: false) }
        try checkStatus(response, data: data)
        return try decode(Drawing.self, from: data)
    }
}

extension ModelInfo {
    /// Whether gglib's model list says this model draws pictures:
    /// `image_generation` in its `capabilities`. Such a model cannot chat,
    /// and gglib refuses a chat sent to it by name.
    public var generatesImages: Bool {
        capabilities?.contains("image_generation") == true
    }

    /// Whether a conversation can be had with this model: it neither draws
    /// pictures nor serves embeddings, which gglib's list says with
    /// `embeddings`, and gglib refuses a chat sent to either by name.
    /// Another server writes neither word, so every model of its is one.
    public var chats: Bool {
        !generatesImages && capabilities?.contains("embeddings") != true
    }
}

extension ProviderError.Code {
    /// The second line under each drawing code, and nil for any other:
    /// `model_not_found` has none, since it is also a chat model's, and
    /// gglib's own sentence names the model that is gone. Each
    /// says what happened to the picture and what to do next; the server's
    /// own sentence, drawn above it, names the model, the file or the size.
    var drawingHint: String? {
        switch self {
        case .imageModelCannotChat:
            "This model draws pictures and cannot chat. Pick a chat model, and press Draw to ask it for a picture."
        case .drawingUnavailable:
            "The serving machine has nothing to draw with for this message. It needs an image model with all its "
                + "files, and a default one when it has several."
        case .invalidImageSize:
            "The image model does not draw that size. Ask for a size the server's sentence names."
        case .imageGenerationFailed:
            "No picture was drawn. Ask again, or for another picture or size."
        case .imageRenderStalled:
            "The picture stopped making progress, so the image model was stopped. Ask again."
        case .imageRuntimeNotInstalled:
            "The serving machine has no image runtime. Install it there with "
                + "\u{201C}gglib config sd install\u{201D}."
        case .imageModelIncomplete:
            "The image model is missing a file it needs. The server's sentence names it and the command that "
                + "links it on the serving machine."
        case .imageModelDoesNotFit:
            "The image model needs more memory than is free while another reply is being written there. Ask "
                + "again when that reply has ended."
        case .notAnImageModel:
            "The model chosen to draw with is not an image model. Pick another image model."
        default:
            nil
        }
    }
}
