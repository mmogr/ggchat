import Foundation
import GGChatCore

extension AppModel {
    /// The request that sends `messages` to `model` through `config`. A send,
    /// Continue and Retry build it here, and so does a run's `PUT` sent
    /// again, so every one carries the same images and the same flags, and
    /// the conversation's Thinking choice (`thinkingBudget`).
    func chatRequest(
        model: String, messages: [Message], thinkingOff: Bool, for config: ProviderConfig
    ) throws(ImageUnavailable) -> ChatRequest {
        var request = try ChatRequest(
            model: model, messages: messages, returnProgress: asksForProgress(config), imagesFrom: store)
        request.reasoningBudgetTokens = thinkingBudget(off: thinkingOff, model: model, for: config)
        return request
    }
}

extension ChatRequest {
    /// A request whose `images` hold the bytes of every image
    /// `messages` name, read from `store` once per id. The one place an
    /// image's reference becomes its bytes: a message never holds them.
    init(
        model: String, messages: [Message], returnProgress: Bool, imagesFrom store: any ImageStore
    ) throws(ImageUnavailable) {
        var images: [String: Data] = [:]
        for image in messages.flatMap(\.images) where images[image.id] == nil {
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
