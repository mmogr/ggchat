import Foundation
import GGChatCore

extension AppModel {
    /// The request that sends `messages` to `model` through `config`. A send,
    /// Continue and Retry build it here, and so does a run's `PUT` sent
    /// again, so every one carries the same images and the same flags, the
    /// conversation's Thinking choice (`thinkingBudget`), the tools its
    /// replies called when the provider is gglib (`asksForProgress`), which
    /// alone reads them, and whether it
    /// draws: it does when the turn it ends on is a question sent with Draw
    /// pressed, which a Continue's partial reply never is. `imageModel` is
    /// the conversation's choice of image model, which the request names
    /// when it draws, for a hub that lists its image models
    /// (`imageModelToSend`). The latest drawn picture is shown to a model
    /// gglib lists as one that reads images (`showsDrawnPicture`), its bytes
    /// read here. One this device cannot read is left out, not refused as a
    /// question's image is: the person did not send it, and the chat reads
    /// without it.
    func chatRequest(
        model: String, messages: [Message], thinkingOff: Bool, imageModel: UInt64?, for config: ProviderConfig
    ) throws(ImageUnavailable) -> ChatRequest {
        var request = try ChatRequest(
            model: model, messages: messages, returnProgress: asksForProgress(config), imagesFrom: store)
        request.reasoningBudgetTokens = thinkingBudget(off: thinkingOff, model: model, for: config)
        request.replaysToolCalls = asksForProgress(config)
        request.draws = messages.last.map { $0.role == .user && $0.draws } ?? false
        request.imageModelID = request.draws ? imageModelToSend(imageModel, to: config) : nil
        if showsDrawnPicture(to: model, request: request, for: config), let shown = messages.shownPicture,
            let data = try? store.loadImage(id: shown.image.id)
        {
            request.shownPicture = shown
            request.images[shown.image.id] = data
        }
        return request
    }

    /// Whether a request to `model` shows it the drawn picture: only when
    /// it says how the picture was made (`replaysToolCalls`), which only
    /// gglib is sent, and only when gglib lists the model as one that reads
    /// images. A model it does not list is not known to, and is sent the
    /// chat without it rather than refused.
    private func showsDrawnPicture(to model: String, request: ChatRequest, for config: ProviderConfig) -> Bool {
        request.replaysToolCalls && models(for: config.id).first(where: { $0.id == model })?.readsImages == true
    }
}

extension ChatRequest {
    /// A request whose `images` hold the bytes of every image the
    /// questions in `messages` name, read from `store` once per id: a
    /// message never holds them. A reply's images, which a tool made, are
    /// not sent back as the reply's and so are not read here;
    /// `chatRequest` reads the drawn picture it shows.
    init(
        model: String, messages: [Message], returnProgress: Bool, imagesFrom store: any ImageStore
    ) throws(ImageUnavailable) {
        var images: [String: Data] = [:]
        for image in messages.filter({ $0.role != .assistant }).flatMap(\.images) where images[image.id] == nil {
            guard let data = try? store.loadImage(id: image.id) else { throw ImageUnavailable() }
            images[image.id] = data
        }
        self.init(model: model, messages: messages, images: images, returnProgress: returnProgress)
    }
}

/// An image a request names whose bytes this device could not read: gone
/// from the store, or a store that would not read. Nothing is sent, since a
/// turn without its image is a different question.
struct ImageUnavailable: Error, LocalizedError {
    var errorDescription: String? {
        "This device could not read an image in this conversation, so nothing was sent."
    }

    /// As a failure kept on the turn it stopped.
    var failure: Failure {
        Failure(message: errorDescription ?? "", code: nil, whereToLook: .unknown)
    }
}
