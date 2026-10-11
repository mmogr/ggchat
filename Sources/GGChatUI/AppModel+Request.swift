import Foundation
import GGChatCore

extension AppModel {
    /// The request that sends `messages` to `model` through `config`. A send,
    /// Continue and Retry build it here, and so does a run's `PUT` sent
    /// again, so every one carries the same images and the same flags, the
    /// conversation's Thinking choice (`thinkingBudget`), and whether it
    /// draws: it does when the turn it ends on is a question sent with Draw
    /// pressed, which a Continue's partial reply never is.
    func chatRequest(
        model: String, messages: [Message], thinkingOff: Bool, for config: ProviderConfig
    ) throws(ImageUnavailable) -> ChatRequest {
        var request = try ChatRequest(
            model: model, messages: messages, returnProgress: asksForProgress(config), imagesFrom: store)
        request.reasoningBudgetTokens = thinkingBudget(off: thinkingOff, model: model, for: config)
        request.draws = messages.last.map { $0.role == .user && $0.draws } ?? false
        return request
    }
}

extension ChatRequest {
    /// A request whose `images` hold the bytes of every image the
    /// questions in `messages` name, read from `store` once per id. The one
    /// place an image's reference becomes its bytes: a message never holds
    /// them. A reply's images, which a tool made, are not sent back to the
    /// model and so are not read.
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
