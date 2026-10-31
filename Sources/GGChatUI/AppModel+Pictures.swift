import Foundation
import GGChatCore

/// An image opened whole: which one, and where its chat keeps it.
struct EnlargedPicture: Identifiable, Equatable {
    let image: ImageRef
    /// Whether it is a Mac's chat's, read from the Mac into memory.
    let fromHub: Bool
    /// The reply that holds it, in a conversation kept on this device.
    let owner: UUID?

    var id: String { image.id }
}

// A picture the drawing tool made, fixed or drawn again. Offered on such a
// picture only, in either kind of chat, while its Mac can be reached and can
// draw. The picture is sent to the Mac, which draws from it; the result is
// held by the editor and joins the chat only on Keep: a Mac's chat keeps it
// on the Mac, beside the picture it came from, and a conversation kept here
// keeps it in this device's store, on the same reply.
//
// The Mac is looked up each time it is asked for something, never once when
// the editor opens: the background hangs every pipe up, and the pipe that
// comes back answers at another address.
extension AppModel {
    /// What a picture was drawn from, when fixing or redoing it can be
    /// offered, and nil when it cannot: the drawing tool's own words for it.
    ///
    /// A Mac's chat (`fromHub`) knows them from the rows it read, by the
    /// picture's id. A conversation kept here knows them from the reply
    /// `owner` names, when that reply holds the picture and one call that
    /// drew (`Message.drawnPrompt`). A person's own image, another tool's,
    /// and a picture of a reply still being written have none: here
    /// another tool's is one a call of the reply other than the drawing
    /// tool's made (`ToolExchange.images`), and its fix would be kept on
    /// the reply as no call's and so shown to a model as the drawn picture. Nor has one that is not a PNG, which the Mac would refuse, or
    /// any picture while its Mac is out of reach or has nothing to draw
    /// with.
    func drawnPrompt(of image: ImageRef, in owner: UUID?, fromHub: Bool) -> String? {
        guard image.mime == ImageRef.png else { return nil }
        if fromHub {
            guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }),
                canRedraw(on: config)
            else { return nil }
            return open.drawnPrompts[image.id]
        }
        guard let reply = keptReply(owner), reply.message.images.contains(image),
            !reply.message.exchanges.contains(where: {
                $0.name != HubToolCall.drawingTool && $0.images.contains(image.id)
            }),
            let config = provider(for: reply.conversation), canRedraw(on: config)
        else { return nil }
        return reply.message.drawnPrompt
    }

    /// Whether `config`'s machine can be asked to draw from a picture now:
    /// a paired Mac whose pipe is up, which said it can draw or lists an
    /// image model with all its files, since the editor can name one.
    func canRedraw(on config: ProviderConfig) -> Bool {
        guard config.isPairedMac, hubIsReachable(config.id), let said = drawings[config.id] else { return false }
        return said.available || said.models?.contains(where: \.complete) == true
    }

    /// Opens the editor on the image opened whole, where one is offered.
    func editEnlargedPicture() {
        guard let shown = enlarged else { return }
        pictureEditor = pictureEditing(of: shown.image, in: shown.owner, fromHub: shown.fromHub)
    }

    /// The editor is gone: a render it left going is stopped.
    func closePictureEditor() {
        pictureEditor?.leave()
        pictureEditor = nil
    }

    /// The editor's state for a picture, or nil where none is offered
    /// (`drawnPrompt`). Its image model starts at the one the chat chose.
    func pictureEditing(of image: ImageRef, in owner: UUID?, fromHub: Bool) -> PictureEditing? {
        guard let prompt = drawnPrompt(of: image, in: owner, fromHub: fromHub) else { return nil }
        if fromHub {
            guard let open = openedHubChat else { return nil }
            return PictureEditing(
                picture: image, prompt: prompt, drawing: drawings[open.providerID], chosen: open.imageModel,
                work: hubWork(image, in: open))
        }
        guard let reply = keptReply(owner), let providerID = reply.conversation.providerID else { return nil }
        return PictureEditing(
            picture: image, prompt: prompt, drawing: drawings[providerID], chosen: reply.conversation.imageModelID,
            work: PictureWork(
                bytes: { [store] in try? store.loadImage(id: image.id) },
                render: { [weak self] in
                    self?.render($0, on: providerID) ?? Self.told("This phone has closed the chat.")
                },
                store: { data in Self.named(data, like: image) },
                join: { [weak self] named, data throws(PictureKeepFailure) in
                    try self?.keepHere(named, data, on: reply.message.id, in: reply.conversation.id)
                },
                stayAwake: { [weak self] in self?.keepsAwake($0) }))
    }

    /// The reply `owner` names in the conversation open, once written.
    private func keptReply(_ owner: UUID?) -> (conversation: Conversation, message: Message)? {
        guard let owner, let conversation = selectedConversation,
            let message = conversation.messages.first(where: { $0.id == owner }), message.role == .assistant,
            !message.isBeingWritten
        else { return nil }
        return (conversation, message)
    }

    /// A paired Mac as it answers now, with what it is called, or the
    /// sentence that says it does not.
    private func reached(_ providerID: UUID) throws(PictureKeepFailure) -> (mac: any Provider, config: ProviderConfig) {
        guard let config = providers.first(where: { $0.id == providerID }) else {
            throw PictureKeepFailure(words: "This phone no longer has the Mac it was drawn on.")
        }
        guard config.isPairedMac, hubIsReachable(config.id), let mac = makeProvider(for: config) else {
            throw PictureKeepFailure(words: "\(config.name) is unreachable.")
        }
        return (mac, config)
    }

    /// That Mac as the keeper of its own chats.
    private func mac(
        _ providerID: UUID
    ) throws(PictureKeepFailure) -> (hub: any HubChatsProvider, config: ProviderConfig) {
        let (mac, config) = try reached(providerID)
        guard let hub = mac as? any HubChatsProvider else {
            throw PictureKeepFailure(words: "\(config.name) is unreachable.")
        }
        return (hub, config)
    }

    /// Draws a picture again on the Mac as it answers now. One out of reach
    /// is a render that failed, saying so.
    private func render(_ redraw: PictureRedraw, on providerID: UUID) -> AsyncStream<RedrawEvent> {
        do throws(PictureKeepFailure) {
            guard let painter = try reached(providerID).mac as? any PictureProvider else {
                return Self.told("The picture could not be drawn.")
            }
            return painter.redraw(redraw)
        } catch {
            return Self.told(error.words)
        }
    }

    /// A render that says only why it did not start.
    private static func told(_ why: String) -> AsyncStream<RedrawEvent> {
        AsyncStream { continuation in
            continuation.yield(.failed(why))
            continuation.finish()
        }
    }

    /// A drawn picture as a store names it: by its bytes' hash, a PNG, its
    /// size read from the bytes and the source's when they do not read.
    static func named(_ data: Data, like source: ImageRef) -> ImageRef {
        let size = PictureMask.size(of: data)
        return ImageRef(
            id: ImageRef.id(of: data), mime: ImageRef.png, width: size?.width ?? source.width,
            height: size?.height ?? source.height)
    }

    /// Keeps a drawn picture with a conversation kept here: its bytes in
    /// this device's store, as a picture a run drew is kept, and its name
    /// on the reply, after the pictures the reply has. One the reply
    /// already names is not named twice.
    private func keepHere(
        _ named: ImageRef, _ data: Data, on messageID: UUID, in conversationID: UUID
    ) throws(PictureKeepFailure) {
        guard var conversation = conversations.first(where: { $0.id == conversationID }),
            let at = conversation.messages.firstIndex(where: { $0.id == messageID })
        else { throw PictureKeepFailure(words: "This phone no longer has the reply it was drawn for.") }
        do {
            try store.save(image: named, data: data)
        } catch {
            throw PictureKeepFailure(words: StoreDirectory.describe(error))
        }
        guard !conversation.messages[at].images.contains(named) else { return }
        conversation.messages[at].images.append(named)
        update(conversation)
    }

    /// How a picture of the Mac's chat open is drawn again and kept: its
    /// bytes are the ones held in memory, the result is sent to the Mac as
    /// a turn's image is, and `POST chats/{id}/pictures` puts it beside the
    /// one it came from. The chat is then read again, as it is after a
    /// reply; a read that fails takes nothing back, since the Mac kept it.
    private func hubWork(_ image: ImageRef, in open: OpenHubChat) -> PictureWork {
        PictureWork(
            bytes: { [hubImages] in hubImages.data(image.id) },
            render: { [weak self] in
                self?.render($0, on: open.providerID) ?? Self.told("This phone has closed the chat.")
            },
            store: { [weak self] data throws(PictureKeepFailure) in
                guard let (hub, config) = try self?.mac(open.providerID) else { return Self.named(data, like: image) }
                do throws(HubTurnFailure) {
                    return try await hub.uploadImage(data, mime: ImageRef.png)
                } catch {
                    throw PictureKeepFailure(words: Self.words(of: error, on: config))
                }
            },
            join: { [weak self] named, data throws(PictureKeepFailure) in
                guard let self else { return }
                let (hub, config) = try mac(open.providerID)
                do throws(ProviderError) {
                    _ = try await hub.keepPicture(chatID: open.chatID, KeptPicture(from: image.id, image: named.id))
                } catch {
                    throw PictureKeepFailure(words: error.errorDescription ?? "\(config.name) refused it.")
                }
                guard openedHubChat?.providerID == open.providerID, openedHubChat?.chatID == open.chatID else { return }
                // Held from here, so its row does not read it back.
                hubImages.hold(data, for: named.id)
                readHubChat()
            },
            stayAwake: { [weak self] in self?.keepsAwake($0) })
    }

    /// Why the Mac did not take a drawn picture into its store, in words.
    private static func words(of failure: HubTurnFailure, on config: ProviderConfig) -> String {
        switch failure {
        case .takesNoImages: takesNoImagesLine(config)
        case .refused(let error), .lost(let error): error.errorDescription ?? "\(config.name) refused it."
        case .noModel, .replyInProgress, .chatGone, .imageGone: "\(config.name) refused it."
        }
    }
}
