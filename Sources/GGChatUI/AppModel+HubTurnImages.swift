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
        if openHubChatIsWriting || open.changing { return giveBack(draft, Self.busyLine(config)) }
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
            thinking: reply.thinking, answerSaved: reply.answersSaved)
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
    /// or images in them, each with the images it carries. The images a tool
    /// made go to the next assistant row that has words, under its text,
    /// after its own images and in the order the tools made them, as the
    /// reply was drawn while it was written. A reply that never gets words
    /// before the next question or the chat's end is those images alone.
    /// The system prompt, a tool's text and a reply that only called tools
    /// are the Mac's to show.
    static func rows(of chat: HubChatOpen, at stamp: Date) -> [Message] {
        drawn(chat, at: stamp).map(\.message)
    }

    /// The rows drawn, each with the id of the Mac's row it shows, which a
    /// change to the chat names (ADR 0010). A row keeps its id each time the
    /// chat is read, so an editor open on it still names it. A reply that is
    /// a tool's images alone shows the first tool row it draws an image of.
    static func drawn(_ chat: HubChatOpen, at stamp: Date) -> [(message: Message, rowID: Int64)] {
        var rows: [(message: Message, rowID: Int64)] = []
        var made: [ImageRef] = []
        var madeBy: Int64?
        func add(_ row: Int64, _ role: Role, _ content: String, _ images: [ImageRef]) {
            let id = rowUUID(chat: chat.conversation.id, row: row)
            rows.append((Message(id: id, role: role, content: content, createdAt: stamp, images: images), row))
        }
        func madeAlone() {
            guard let row = madeBy, !made.isEmpty else { return }
            add(row, .assistant, "", made)
            made = []
            madeBy = nil
        }
        for row in chat.messages {
            let images = row.images ?? []
            if row.role == "tool" {
                if !images.isEmpty, madeBy == nil { madeBy = row.id }
                made += images
                continue
            }
            guard let role = Role(rawValue: row.role), role != .system, !row.content.isEmpty || !images.isEmpty
            else { continue }
            if role == .assistant, !row.content.isEmpty {
                add(row.id, role, row.content, images + made)
                made = []
                madeBy = nil
            } else if role == .assistant {
                add(row.id, role, row.content, images)
            } else {
                madeAlone()
                add(row.id, role, row.content, images)
            }
        }
        madeAlone()
        return rows
    }

    /// The id a Mac's row is drawn with: the chat's id and the row's, side
    /// by side.
    static func rowUUID(chat: Int64, row: Int64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for at in 0..<8 {
            bytes[at] = UInt8(truncatingIfNeeded: UInt64(bitPattern: chat) >> (56 - 8 * at))
            bytes[8 + at] = UInt8(truncatingIfNeeded: UInt64(bitPattern: row) >> (56 - 8 * at))
        }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

extension HubLiveReply {
    /// The question this phone sent, to draw above the reply until `rows`
    /// end with it. A turn that answers a saved question sent none.
    func questionToDraw(under rows: OpenHubChat.State) -> Message? {
        guard let question, !answersSaved else { return nil }
        if case .read(let messages) = rows, let last = messages.last, last.role == .user, last.content == question,
            last.images.map(\.id) == images.map(\.id)
        {
            return nil
        }
        return Message(role: .user, content: question, createdAt: .distantPast, images: images.map(\.ref))
    }

    /// What this phone sent, as a draft to give back when the Mac refuses
    /// it: the text and the images, bytes and all. A turn that answers a
    /// saved question sent none.
    var unsent: Draft? {
        answersSaved ? nil : question.map { Draft(text: $0, images: images) }
    }
}
