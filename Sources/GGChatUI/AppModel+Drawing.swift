import Foundation
import GGChatCore

// Drawing, from either kind of chat. gglib draws with an image model on the
// machine it runs on, and only for a message sent with Draw pressed: the
// switch is the composer's, set for one message and off again once it is
// sent. Whether a hub can draw is asked of it, never guessed, and a hub that
// cannot is never sent the word.
extension AppModel {
    /// Asks a paired Mac whether it can draw, and keeps what it says in
    /// memory. A server added by address is not asked: gglib draws only for
    /// a device it has paired, which a caller by address is not. An answer
    /// that fails keeps the one before, and is logged by its code.
    func askAboutDrawing(_ config: ProviderConfig) async {
        guard config.isPipe, let hub = makeProvider(for: config) as? any DrawingProvider else { return }
        do throws(ProviderError) {
            let answer = try await hub.drawing()
            // An edit may have moved the provider while this waited.
            guard providers.first(where: { $0.id == config.id })?.kind == config.kind else { return }
            drawings[config.id] = answer
        } catch {
            log.log(.info, "\(config.name) did not say whether it can draw: \(error.code ?? "no code")")
        }
    }

    /// Why a message cannot be drawn on `config`'s machine now, or nil when
    /// it can: gglib's own reason, a sentence for a gglib from before
    /// drawing, which answers nothing, and one for a hub not asked yet.
    func drawRefusal(on config: ProviderConfig) -> String? {
        guard let answer = drawings[config.id] else {
            return "It is not known yet whether \(config.name) can draw."
        }
        if answer.available { return nil }
        guard let reason = answer.reason, !reason.isEmpty else {
            return "The gglib on \(config.name) needs updating before it can draw."
        }
        return "\(config.name) cannot draw: \(reason)"
    }

    /// Whether the conversation's composer has a Draw switch: its provider
    /// is gglib (`asksForProgress`). Another server has none.
    public func offersDrawing(for conversation: Conversation) -> Bool {
        provider(for: conversation).map(asksForProgress) ?? false
    }

    /// What the switch says for a gglib reached by its address. gglib
    /// starts a run that draws, and hands over the picture, only for a
    /// device it has paired; a caller by address is refused both.
    static let needsAPairedMac = "Drawing needs a paired Mac."

    /// Why the conversation's next message cannot be drawn, or nil when it
    /// can, which only a paired Mac's can.
    public func drawRefusal(for conversation: Conversation) -> String? {
        guard let config = provider(for: conversation) else { return "This conversation has no provider." }
        return config.isPipe ? drawRefusal(on: config) : Self.needsAPairedMac
    }

    /// Why the next message to the Mac's chat open cannot be drawn, or nil
    /// when it can.
    public var hubDrawRefusal: String? {
        guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }) else {
            return "No chat is open."
        }
        return drawRefusal(on: config)
    }

    /// Keeps the bytes of the images a run's frame names, before the frame
    /// is applied: each read from the hub by its id, once, and stored under
    /// that id as a question's images are, since a conversation kept here
    /// owns its images and the hub lets go of one no chat of its own names.
    /// One already in the store is not read again.
    ///
    /// Answers false when an image was lost on the way, and the frame is
    /// then not applied: the run is read on from the frame before it, and
    /// the image asked for again. An image the hub no longer has, or whose
    /// bytes are not the ones its id names, is passed over: the reply names
    /// it, and it is drawn as one this device does not have.
    func keepImages(named events: [ChatEvent], from hub: any RunProvider) async -> Bool {
        for case .images(let images) in events {
            for image in images where (try? store.loadImage(id: image.id)) == nil {
                let data: Data
                do throws(HubChatsFailure) {
                    data = try await hub.fetchImage(id: image.id)
                } catch {
                    if case .dropped = error { return false }
                    log.log(.info, "a hub did not send an image its run made: \(Self.kind(of: error))")
                    continue
                }
                guard ImageRef.id(of: data) == image.id else {
                    log.log(.info, "a hub sent an image whose bytes are not its id")
                    continue
                }
                do {
                    try store.save(image: image, data: data)
                } catch {
                    log.log(.error, "could not keep an image a run made (\(StoreDirectory.describe(error)))")
                }
            }
        }
        return true
    }
}
