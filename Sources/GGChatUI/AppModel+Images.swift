import CoreGraphics
import Foundation
import GGChatCore

extension AppModel {
    /// Whether the model this conversation talks to can be sent images. A
    /// gglib server, one asked for progress (`asksForProgress`), lists which
    /// of its models read images, and a model it lists without `vision`
    /// cannot. Any other server, and a model gglib's list does not name, is
    /// not known either way and is sent them: a refusal then comes back by
    /// name. The attach control and a send both ask here.
    func canSee(_ conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation), asksForProgress(config),
            let modelID = conversation.model ?? config.defaultModel,
            let listed = models(for: config.id).first(where: { $0.id == modelID })
        else { return true }
        return listed.readsImages
    }

    /// Whether an image may join a draft for this conversation now. One for
    /// a model that cannot see is refused at once, with `cannotSee`, rather
    /// than when the draft is sent.
    func admitsImages(to conversation: Conversation) -> Bool {
        guard canSee(conversation) else {
            lastError = Self.cannotSee
            return false
        }
        return true
    }

    /// What a model that cannot read images is refused with here: gglib's
    /// own sentence for `model_cannot_read_images`, so the app and the
    /// server say the same thing.
    static var cannotSee: String {
        ProviderError.Code.modelCannotReadImages.hint ?? ""
    }

    /// Sends the composer's draft as the open conversation's next turn: its
    /// text, its images, or both. Answers whether it was taken.
    ///
    /// A draft with images to a model that cannot see is refused here, with
    /// `cannotSee`, and so is one whose images this device could not keep;
    /// the composer keeps a refused draft as it was. Once taken, the turn is
    /// the conversation's, with its images kept under their ids: a refusal
    /// from the server is drawn under it, and Retry sends it again, images
    /// and all.
    @discardableResult
    func send(_ text: String, images: [DraftImage]) -> Bool {
        guard let conversation = selectedConversation, takesTurn(conversation) else { return false }
        if !images.isEmpty, !canSee(conversation) {
            lastError = Self.cannotSee
            return false
        }
        do {
            for image in images {
                try store.save(image: image.ref, data: image.data)
            }
        } catch {
            report(error)
            forget(images)
            return false
        }
        guard let turn = appendTurn(text, images: images.map(\.ref)) else {
            forget(images)
            return false
        }
        stream(turn, continuing: nil)
        return true
    }

    /// Takes back the bytes a refused draft's images left in the store, each
    /// one no kept turn names; an image an earlier turn sent stays.
    private func forget(_ images: [DraftImage]) {
        do {
            try store.deleteImages(noTurnNames: Set(images.map(\.id)))
        } catch {
            log.log(.error, "could not take back a refused draft's images: \(type(of: error))")
        }
    }

    /// A small upright picture of a kept image, for a row, read from the
    /// store once and then remembered; nil when this device does not have
    /// it.
    func thumbnail(of image: ImageRef) -> CGImage? {
        if let kept = thumbnails.object(forKey: image.id as NSString) { return kept }
        guard let data = try? store.loadImage(id: image.id), let picture = ImageDownscale.thumbnail(of: data)
        else { return nil }
        thumbnails.setObject(picture, forKey: image.id as NSString)
        return picture
    }

    /// A kept image at its own size, upright, for a look at it whole.
    func picture(of image: ImageRef) -> CGImage? {
        guard let data = try? store.loadImage(id: image.id) else { return nil }
        return ImageDownscale.thumbnail(of: data, longEdge: max(image.width, image.height, 1))
    }
}
