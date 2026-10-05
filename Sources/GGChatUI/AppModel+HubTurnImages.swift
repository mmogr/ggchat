import Foundation
import GGChatCore

// A turn to a Mac's chat with images. Each image is sent to the Mac first,
// `POST attachments`, and the turn names them by the ids the Mac answers.
// Their bytes are held in memory only, by the reply until its run ends and by
// a draft given back, and the Mac's own images are read into memory as its
// rows are drawn: nothing of either is written to this phone (ADR 0007).
extension AppModel {
    /// Sends `text` and `images` as a turn on the chat open, and reads the
    /// Mac's reply. A turn may be text, images, or both. Refused here while
    /// the chat has a reply being written, when its Mac cannot be reached,
    /// and with images when this phone knows the chat's model cannot see,
    /// each with a sentence in the view and the draft given back.
    @discardableResult
    func sendToHubChat(_ text: String, images: [DraftImage] = []) -> Task<Void, Never>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty, let open = openedHubChat,
            let config = providers.first(where: { $0.id == open.providerID })
        else { return nil }
        let draft = Draft(text: trimmed, images: images)
        if !images.isEmpty, !canSeeHubChat(open) { return giveBack(draft, Self.cannotSee) }
        if openHubChatIsWriting { return giveBack(draft, Self.busyLine(config)) }
        guard let hub = reachableHubChats(for: config) else {
            return giveBack(draft, "\(config.name) is unreachable.")
        }
        openedHubChat?.notice = nil
        openedHubChat?.unsent = nil
        hubReplies.removeAll { $0.chatID == open.chatID && $0.providerID == open.providerID }
        for image in images { hubImages.hold(image.data, for: image.id) }
        // The choice is said only while it is not what the Mac remembers.
        let reply = HubLiveReply(
            providerID: config.id, chatID: open.chatID, runID: UUID().uuidString, question: trimmed,
            images: images, thinking: open.thinking.change)
        hubReplies.append(reply)
        let task = Task { [weak self] in
            guard let self else { return }
            await putTurn(reply, on: hub, config)
        }
        reply.reading = task
        return task
    }

    /// A send that went nowhere: why, in the view, and the draft back in
    /// the composer.
    private func giveBack(_ draft: Draft, _ why: String) -> Task<Void, Never>? {
        openedHubChat?.notice = why
        openedHubChat?.unsent = draft
        return nil
    }

    /// Whether the chat open's model can be sent images, as far as this
    /// phone knows: the chat's model (`hubChatModel`), looked up in the
    /// models this phone last read from that Mac. A chat that names none, or
    /// a model this phone has not read, is sent them, and the Mac refuses by
    /// name a model that cannot read them.
    func canSeeHubChat(_ open: OpenHubChat) -> Bool {
        hubChatModel(open)?.readsImages ?? true
    }

    /// Whether an image may join the draft of the chat open now. One for a
    /// model that cannot see is refused at once, with `cannotSee`.
    func admitsImagesToHubChat() -> Bool {
        guard let open = openedHubChat, canSeeHubChat(open) else {
            lastError = Self.cannotSee
            return false
        }
        return true
    }

    /// Sends the reply's images the Mac does not hold yet, then puts its
    /// turn naming them. A turn refused because the Mac no longer holds one
    /// of them started no run: they are sent again from the bytes held here,
    /// and the turn is put again under the same id, once.
    func startTurn(_ reply: HubLiveReply, on hub: any HubChatsProvider) async throws(HubTurnFailure) -> RunStart {
        do throws(HubTurnFailure) {
            return try await hub.startTurn(runID: reply.runID, turn: turn(of: reply, hub))
        } catch .imageGone where !reply.images.isEmpty {
            reply.uploaded = nil
            log.log(.info, "a turn named an image the Mac no longer holds, so its images are sent again")
            return try await hub.startTurn(runID: reply.runID, turn: turn(of: reply, hub))
        }
    }

    /// The reply's turn as it is put, each time it is: its text, the ids of
    /// its images, and what it says of the Thinking choice.
    private func turn(of reply: HubLiveReply, _ hub: any HubChatsProvider) async throws(HubTurnFailure) -> HubTurn {
        HubTurn(
            conversationID: reply.chatID, content: reply.question ?? "", images: try await imageIDs(reply, hub),
            thinking: reply.thinking)
    }

    /// The ids the Mac holds the reply's images under, each sent to it the
    /// first time they are asked for.
    private func imageIDs(_ reply: HubLiveReply, _ hub: any HubChatsProvider) async throws(HubTurnFailure) -> [String] {
        if let held = reply.uploaded { return held }
        var ids: [String] = []
        for image in reply.images {
            ids.append(try await hub.uploadImage(image.data, mime: image.ref.mime).id)
        }
        reply.uploaded = ids
        return ids
    }

    /// The draft a send that went nowhere left, for the composer to take
    /// back; nil once taken.
    func takeUnsentHubDraft() -> Draft? {
        defer { openedHubChat?.unsent = nil }
        return openedHubChat?.unsent
    }

    /// What the view says to a Mac whose gglib is from before images.
    static func takesNoImagesLine(_ config: ProviderConfig) -> String {
        "The gglib on \(config.name) needs updating before it can take images."
    }

    /// The rows this phone draws: the questions and the replies with words
    /// or images in them, each with the images it carries. The system
    /// prompt, tool results and a reply that only called tools are the
    /// Mac's to show.
    static func rows(of chat: HubChatOpen, at stamp: Date) -> [Message] {
        chat.messages.compactMap { row in
            let images = row.images ?? []
            guard let role = Role(rawValue: row.role), role != .system, !row.content.isEmpty || !images.isEmpty
            else { return nil }
            return Message(role: role, content: row.content, createdAt: stamp, images: images)
        }
    }
}

extension HubLiveReply {
    /// What this phone sent, as a draft to give back when the Mac refuses
    /// it: the text and the images, bytes and all.
    var unsent: Draft? {
        question.map { Draft(text: $0, images: images) }
    }
}
