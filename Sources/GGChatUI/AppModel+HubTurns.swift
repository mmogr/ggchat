import Foundation
import GGChatCore

// Carrying a Mac's chat on from this phone. A send puts the new text alone as
// a turn; the Mac rebuilds the history from its own record, runs the reply
// as an agent run, and saves both rows. The reply is read from the run's
// events into memory, and once the run ends the Mac's rows are read in its
// place. Nothing of it is written to this phone's store (ADR 0007).
extension AppModel {
    /// The reply this phone holds for one of a Mac's chats, ended or not.
    func hubReply(for chatID: Int64, on providerID: UUID) -> HubLiveReply? {
        hubReplies.first { $0.chatID == chatID && $0.providerID == providerID }
    }

    /// The reply to the chat open, while one is drawn under it.
    public var openHubReply: HubLiveReply? {
        openedHubChat.flatMap { hubReply(for: $0.chatID, on: $0.providerID) }
    }

    /// Whether the chat open has a reply being written: its send is Stop.
    public var openHubChatIsWriting: Bool {
        openHubReply.map { !$0.ended } ?? false
    }

    /// Sends `text` as a turn on the chat open, and reads the Mac's reply.
    /// Refused here while the chat has a reply being written, and when its
    /// Mac cannot be reached, each with a sentence in the view.
    @discardableResult
    public func sendToHubChat(_ text: String) -> Task<Void, Never>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let open = openedHubChat,
            let config = providers.first(where: { $0.id == open.providerID })
        else { return nil }
        if openHubChatIsWriting {
            openedHubChat?.notice = Self.busyLine(config)
            return nil
        }
        guard let hub = reachableHubChats(for: config) else {
            openedHubChat?.notice = "\(config.name) is unreachable."
            return nil
        }
        openedHubChat?.notice = nil
        hubReplies.removeAll { $0.chatID == open.chatID && $0.providerID == open.providerID }
        let reply = HubLiveReply(
            providerID: config.id, chatID: open.chatID, runID: UUID().uuidString, question: trimmed)
        hubReplies.append(reply)
        let task = Task { [weak self] in
            guard let self else { return }
            await putTurn(reply, on: hub, config)
        }
        reply.reading = task
        return task
    }

    /// Stop, under the chat open's reply: the run is cancelled on the Mac,
    /// and the Mac's rows are read once it has ended. A reply nobody is
    /// reading is cancelled at once, and one whose Mac cannot be reached is
    /// given up here, so Stop is always a way out.
    public func stopHubReply() {
        guard let reply = openHubReply, !reply.ended else { return }
        if let reading = reply.reading { return reading.cancel() }
        guard let config = providers.first(where: { $0.id == reply.providerID }),
            let hub = reachableHubChats(for: config)
        else { return endHubReply(reply) }
        reply.reading = Task { [weak self] in
            guard let self else { return }
            await putDown(reply, on: hub, config)
        }
    }

    /// Sends the turn's `PUT` and reads the reply. A refusal says why and
    /// keeps nothing.
    func putTurn(_ reply: HubLiveReply, on hub: any HubChatsProvider, _ config: ProviderConfig) async {
        guard let question = reply.question else { return }
        let start: RunStart
        do throws(HubTurnFailure) {
            start = try await hub.startTurn(
                runID: reply.runID, turn: HubTurn(conversationID: reply.chatID, content: question))
        } catch {
            guard !Task.isCancelled else { return await putDown(reply, on: hub, config) }
            // Lost on the way, and it may have arrived: the id is kept, and
            // the next read puts it again.
            if case .lost = error { return walkAway(reply, readAny: false) }
            return refuse(reply, Self.refusalLine(error, config), config)
        }
        reply.started = true
        keepHubRuns(reply.providerID)
        guard !Task.isCancelled else { return await putDown(reply, on: hub, config) }
        switch start {
        case .started:
            await readTurn(reply, on: hub, config)
        case .unsupported:
            refuse(reply, "\(config.name) cannot carry its chats on from this phone yet.", config)
        }
    }

    /// Reads the run's events after the reply's cursor, each frame applied
    /// whole and never twice, then ends the reply as the run ended.
    func readTurn(_ reply: HubLiveReply, on hub: any HubChatsProvider, _ config: ProviderConfig) async {
        var end: RunEvent?
        var readAny = false
        for await event in hub.turnEvents(runID: reply.runID, after: reply.cursor) {
            guard case .frame(let seq, let events) = event else {
                end = event
                continue
            }
            guard seq > reply.cursor else { continue }
            for chat in events { reply.apply(chat) }
            reply.cursor = seq
            readAny = true
        }
        switch end {
        case .ended(let info)? where info.status.isTerminal:
            let failure = info.status == .failed ? info.error?.message ?? "the run failed" : nil
            endHubReply(reply, notice: failure.map { "The reply stopped on \(config.name): \($0)" })
        case .notFound?:
            endHubReply(reply)
        case .refused(let error)?:
            log.log(.info, "a turn's run was refused with \(error.code ?? "no code"), so it is given up")
            endHubReply(reply, notice: "\(config.name) would not send the rest of this reply.")
        default:
            guard !Task.isCancelled else { return await putDown(reply, on: hub, config) }
            walkAway(reply, readAny: readAny)
        }
    }

    /// The reading was put down. Leaving the chat, or the background, walks
    /// away from the run and keeps the reply. Stop cancels the run on the Mac
    /// and reads on to its end, so the rows read then hold what it saved.
    func putDown(_ reply: HubLiveReply, on hub: any HubChatsProvider, _ config: ProviderConfig) async {
        reply.reading = nil
        if reply.detaching {
            // Its chat may have been opened again while it stopped.
            reply.detaching = false
            return readOnHubReply()
        }
        let cancelled = await Task { [log] () -> Bool in
            do throws(ProviderError) {
                _ = try await hub.cancelTurn(runID: reply.runID)
                return true
            } catch {
                log.log(.info, "a turn could not be cancelled: \(error.code ?? "no code")")
                return false
            }
        }.value
        guard cancelled, reply.started else { return endHubReply(reply) }
        reply.reading = Task { [weak self] in
            guard let self else { return }
            await readTurn(reply, on: hub, config)
        }
    }

    /// The run has ended: the reply is forgotten, and the Mac's rows are read
    /// in its place when its chat is open. It stays on screen until they are.
    func endHubReply(_ reply: HubLiveReply, notice: String? = nil) {
        reply.reading = nil
        reply.ended = true
        readOnAttempts[reply.key] = nil
        keepHubRuns(reply.providerID)
        guard openedHubChat?.providerID == reply.providerID, openedHubChat?.chatID == reply.chatID else {
            return hubReplies.removeAll { $0 === reply }
        }
        if let notice { openedHubChat?.notice = notice }
        readHubChat()
    }

    /// The Mac did not start the turn: the reply goes, and the view says why.
    private func refuse(_ reply: HubLiveReply, _ why: String, _ config: ProviderConfig) {
        reply.reading = nil
        hubReplies.removeAll { $0 === reply }
        guard openedHubChat?.providerID == reply.providerID, openedHubChat?.chatID == reply.chatID else { return }
        openedHubChat?.notice = why
        log.log(.info, "\(config.name) did not start a turn")
    }

    /// Drops the ended replies of a chat, whose rows now hold them.
    func dropEndedHubReplies(_ chatID: Int64, on providerID: UUID) {
        hubReplies.removeAll { $0.ended && $0.chatID == chatID && $0.providerID == providerID }
    }

    /// Walks away from the reply to a chat being left: the Mac goes on
    /// writing it, and the reply is kept.
    func detachHubReply(_ chatID: Int64, on providerID: UUID) {
        dropEndedHubReplies(chatID, on: providerID)
        guard let reply = hubReply(for: chatID, on: providerID), let reading = reply.reading else { return }
        reply.detaching = true
        reading.cancel()
    }

    /// Forgets the replies to a removed provider's chats. The Mac goes on
    /// writing them.
    func forgetHubReplies(_ providerID: UUID) {
        for reply in hubReplies where reply.providerID == providerID {
            reply.detaching = true
            reply.reading?.cancel()
        }
        hubReplies.removeAll { $0.providerID == providerID }
    }

    static func busyLine(_ config: ProviderConfig) -> String {
        "A reply is already being written on \(config.name)."
    }

    /// What the view says when the Mac did not start a turn.
    static func refusalLine(_ failure: HubTurnFailure, _ config: ProviderConfig) -> String {
        switch failure {
        case .noModel: "This chat has no model; pick one on \(config.name)."
        case .replyInProgress: busyLine(config)
        case .chatGone: "\(config.name) no longer has this chat."
        case .refused(let error), .lost(let error):
            "\(config.name) did not take this message. \(error.errorDescription ?? "")"
                .trimmingCharacters(in: .whitespaces)
        }
    }
}
