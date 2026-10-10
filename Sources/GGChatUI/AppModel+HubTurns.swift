import Foundation
import GGChatCore

// Carrying a Mac's chat on from this phone. A send puts the new text and the
// ids of its images as a turn (`AppModel+HubTurnImages`); the Mac rebuilds
// the history from its own record, runs the reply as an agent run, and saves
// both rows. The reply is read from the run's events into memory, and once
// the run ends the Mac's rows are read in its place. Nothing of it is written
// to this phone's store (ADR 0007).
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
        guard reply.question != nil else { return }
        let start: RunStart
        do throws(HubTurnFailure) {
            start = try await startTurn(reply, on: hub)
        } catch {
            guard !Task.isCancelled else { return await putDown(reply, on: hub, config) }
            // Lost on the way, and it may have arrived: the id is kept, and
            // the next read puts it again.
            if case .lost = error { return walkAway(reply, readAny: false) }
            return refuse(reply, Self.refusalLine(error, config), config)
        }
        // A gglib that does not know turns takes one for a chat run, which
        // fails on the way to the model: it is stopped, and said as a hub
        // without them.
        if case .started(let info) = start, info.kind != .agent {
            cancelTurn(reply.runID, on: hub)
            return refuse(reply, Self.unsupportedLine(config), config)
        }
        reply.started = true
        hubTookTurn(reply)
        keepHubRuns(reply.providerID)
        guard !Task.isCancelled else { return await putDown(reply, on: hub, config) }
        switch start {
        case .started:
            await readTurn(reply, on: hub, config)
        case .unsupported:
            refuse(reply, Self.unsupportedLine(config), config)
        }
    }

    /// Reads the run's events after the reply's cursor, each frame applied
    /// whole and never twice, then ends the reply as the run ended. A look
    /// at a picture being drawn is shown and moves no cursor.
    func readTurn(_ reply: HubLiveReply, on hub: any HubChatsProvider, _ config: ProviderConfig) async {
        var end: RunEvent?
        var readAny = false
        for await event in hub.turnEvents(runID: reply.runID, after: reply.cursor) {
            if case .preview(let frame) = event {
                reply.work.show(frame)
                continue
            }
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
        if reply.detaching {
            // Its chat may have been opened again while it stopped.
            reply.reading = nil
            reply.detaching = false
            return readOnHubReply()
        }
        // The reading stays set until the cancel is answered, so nothing
        // reads on beside it in the meantime.
        let cancelled = await cancelTurn(reply.runID, on: hub).value
        guard cancelled, reply.started else { return endHubReply(reply) }
        reply.reading = Task { [weak self] in
            guard let self else { return }
            await readTurn(reply, on: hub, config)
        }
    }

    /// Cancels a turn's run in a task of its own, since the caller's may be
    /// cancelled already, and says whether the Mac took the cancel.
    @discardableResult
    func cancelTurn(_ runID: String, on hub: any HubChatsProvider) -> Task<Bool, Never> {
        Task { [log] () -> Bool in
            do throws(ProviderError) {
                _ = try await hub.cancelTurn(runID: runID)
                return true
            } catch {
                log.log(.info, "a turn could not be cancelled: \(error.code ?? "no code")")
                return false
            }
        }
    }

    /// The run has ended: the reply is forgotten, and the Mac's rows are read
    /// in its place when its chat is open. It stays on screen until they are.
    func endHubReply(_ reply: HubLiveReply, notice: String? = nil) {
        reply.reading = nil
        reply.ended = true
        reply.work.end()
        readOnAttempts[reply.key] = nil
        keepHubRuns(reply.providerID)
        guard openedHubChat?.providerID == reply.providerID, openedHubChat?.chatID == reply.chatID else {
            return hubReplies.removeAll { $0 === reply }
        }
        if let notice { openedHubChat?.notice = notice }
        readHubChat()
    }

    /// The Mac did not start the turn: the reply goes, the view says why,
    /// and the text and images go back into the composer.
    private func refuse(_ reply: HubLiveReply, _ why: String, _ config: ProviderConfig) {
        reply.reading = nil
        hubReplies.removeAll { $0 === reply }
        guard openedHubChat?.providerID == reply.providerID, openedHubChat?.chatID == reply.chatID else {
            return keepRefused(reply, why)
        }
        openedHubChat?.notice = why
        openedHubChat?.unsent = reply.unsent
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
        refusedHubSends[providerID] = nil
    }

    static func unsupportedLine(_ config: ProviderConfig) -> String {
        "\(config.name) cannot carry its chats on from this phone yet."
    }

    static func busyLine(_ config: ProviderConfig) -> String {
        "A reply is already being written on \(config.name)."
    }

    /// What the view says when the Mac did not start a turn.
    static func refusalLine(_ failure: HubTurnFailure, _ config: ProviderConfig) -> String {
        switch failure {
        case .noModel: "This chat has no model and nothing is running on \(config.name). Start a model there."
        case .replyInProgress: busyLine(config)
        case .chatGone: "\(config.name) no longer has this chat."
        case .imageGone: "\(config.name) no longer has an image this chat carries."
        case .takesNoImages: takesNoImagesLine(config)
        case .refused(let error) where error.code == BranchRefusal.nothingToAnswer.code:
            sentence(for: .nothingToAnswer) ?? ""
        case .refused(let error), .lost(let error):
            "\(config.name) did not take this message. \(error.errorDescription ?? "")"
                .trimmingCharacters(in: .whitespaces)
        }
    }
}
