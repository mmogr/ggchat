import Foundation
import GGChatCore

// A reply to gglib is a run: the hub writes it whether or not this device is
// there to read it (ADR 0002, amended 2026-09-29). Going to the background,
// or losing the connection, walks away from the run and keeps its id and the
// last event read with the message; coming back reads on from there. Only
// Stop, or deleting what it belongs to, cancels it.
extension AppModel {
    /// The provider as a hub to start a run on, or nil when this reply goes
    /// the old way: the provider is not gglib, or has said it has no runs.
    func runHub(_ provider: any Provider, for config: ProviderConfig) -> (any RunProvider)? {
        guard asksForProgress(config), !providersWithoutRuns.contains(config.id) else { return nil }
        return provider as? any RunProvider
    }

    /// Starts the reply as a run under an id minted here, and reads it. A hub
    /// that answers as one without runs is remembered, and this reply and the
    /// rest to it go the old way, with nothing shown.
    func startRun(_ request: ChatRequest, on hub: any RunProvider, for config: ProviderConfig, live: LiveReply) async {
        // Set before the request, so a reply put down while it is on its way
        // still names the run it may have started.
        let id = UUID().uuidString
        live.runID = id
        let start: RunStart
        do {
            start = try await hub.startRun(id: id, request)
        } catch {
            guard !Task.isCancelled else { return await putDown(live, on: hub) }
            live.runID = nil
            live.error = error
            return finish(live, finished: false, cancelled: false)
        }
        guard !Task.isCancelled else { return await putDown(live, on: hub) }
        switch start {
        case .started:
            await readRun(on: hub, live: live)
        case .unsupported:
            log.log(.info, "\(config.name) has no runs, so replies to it stream as they did")
            providersWithoutRuns.insert(config.id)
            live.runID = nil
            await streamChat(request, on: hub, live: live)
        }
    }

    /// Reads the run's events after the reply's cursor, applying each frame
    /// whole and moving the cursor with it, then ends the reply as the run
    /// did, or walks away from the run when the reading stopped first.
    func readRun(on hub: any RunProvider, live: LiveReply) async {
        guard let id = live.runID else { return }
        var end: RunEvent?
        var readAny = false
        for await event in hub.runEvents(id: id, after: live.cursor) {
            guard case .frame(let seq, let events) = event else {
                end = event
                continue
            }
            // Never applied twice, whatever the hub sends.
            guard seq > live.cursor else { continue }
            for chat in events { apply(chat, to: live) }
            live.cursor = seq
            readAny = true
        }
        switch end {
        case .ended(let info)? where info.status.isTerminal:
            endReply(live, as: info)
            readOnDetachedRuns()
        case .notFound?:
            lose(live)
            readOnDetachedRuns()
        default:
            guard !Task.isCancelled else { return await putDown(live, on: hub) }
            // The connection went, not the run: walk away and read on once
            // the hub can be reached. At once only when this reading got
            // somewhere, so a hub that cannot be reached is not asked again
            // and again.
            finish(live, finished: false, cancelled: true, keepsRun: true)
            guard readAny else { return }
            let kept = conversations.first { $0.id == live.conversationID }?.messages.last(where: \.isBeingWritten)
            readOnDetachedRuns(preferring: kept?.id)
        }
    }

    /// Ends the reply as the run's last report says it ended.
    private func endReply(_ live: LiveReply, as info: RunInfo) {
        switch info.status {
        case .completed:
            live.error = nil
            finish(live, finished: true, cancelled: false)
        case .failed:
            let reported = info.error.map { ProviderError.stream(code: $0.code, message: $0.message) }
            live.error = live.error ?? reported ?? .stream(code: nil, message: "the run failed")
            finish(live, finished: false, cancelled: false)
        case .cancelled, .queued, .inProgress:
            finish(live, finished: false, cancelled: true)
        }
    }

    /// The hub no longer has the run: what arrived stays, with Continue, and
    /// a sentence that says why the rest will not.
    private func lose(_ live: LiveReply) {
        let name = conversations.first { $0.id == live.conversationID }.flatMap(provider(for:))?.name
        let sentence = "\(name ?? "The machine") no longer has the rest of this reply."
        finish(
            live, finished: false, cancelled: false,
            refusal: Failure(message: sentence, code: RunCode.notFound, whereToLook: .unknown))
    }

    /// The reply was put down. On the way to the background it walks away from
    /// the run; otherwise, Stop or a deletion, the run is cancelled on the hub
    /// and the reply ends as a stopped one. The cancel goes in a task of its
    /// own, since this one is cancelled and would call it off at once.
    private func putDown(_ live: LiveReply, on hub: any RunProvider) async {
        guard let id = live.runID, !live.detaching else {
            return finish(live, finished: false, cancelled: true, keepsRun: live.runID != nil)
        }
        let cancel = Task { [log] in
            do {
                _ = try await hub.cancelRun(id: id)
            } catch {
                log.log(.info, "a run could not be cancelled: \(error.localizedDescription)")
            }
        }
        finish(live, finished: false, cancelled: true)
        await cancel.value
    }

    // MARK: - Reading on

    /// Coming back, and at launch: dials the pipes behind replies still being
    /// written, and reads on through the hubs that can be reached now. A pipe
    /// reads on once it comes up; see `setPipeStatus`.
    func resumeRuns() {
        let pipes = Set(conversations.filter { $0.messages.contains(where: \.isBeingWritten) }.compactMap(\.providerID))
        for config in providers where config.isPipe && pipes.contains(config.id) && pipeSessions[config.id] == nil {
            Task { await connectPipe(for: config, quietly: true) }
        }
        readOnDetachedRuns()
    }

    /// Reads on from one reply still being written whose hub can be reached
    /// now: `preferring` first, then the open conversation's, then the rest.
    /// One at a time, as every reply in flight is, and none while one is.
    func readOnDetachedRuns(preferring messageID: UUID? = nil) {
        guard liveReply == nil, !isAway else { return }
        let ordered =
            conversations.filter { $0.id == selectedConversationID }
            + conversations.filter { $0.id != selectedConversationID }
        for conversation in ordered {
            guard let message = conversation.messages.last(where: \.isBeingWritten),
                messageID == nil || message.id == messageID
            else { continue }
            if readOn(message, in: conversation) { return }
        }
        if messageID != nil { readOnDetachedRuns() }
    }

    /// Starts reading on from one detached reply, and says whether it did:
    /// not when its hub cannot be reached now.
    private func readOn(_ message: Message, in conversation: Conversation) -> Bool {
        let live = LiveReply(conversationID: conversation.id, continuingMessageID: message.id)
        live.runID = message.runID
        live.cursor = message.runCursor ?? 0
        guard let config = provider(for: conversation) else {
            // Its provider is gone, and the hub with it.
            lose(live)
            return false
        }
        let connected = pipeSessions[config.id] != nil && pipeStatuses[config.id]?.isConnected == true
        guard !config.isPipe || connected, let hub = makeProvider(for: config) as? any RunProvider else {
            return false
        }
        liveReply = live
        streamTask = Task { [weak self] in await self?.readRun(on: hub, live: live) }
        return true
    }

    /// Cancels, on their hubs, the runs still writing replies in a
    /// conversation that is going away.
    func stopDetachedRuns(in conversation: Conversation) {
        guard let config = provider(for: conversation) else { return }
        let ids = conversation.messages.compactMap(\.runID)
        let reachable = !config.isPipe || pipeSessions[config.id] != nil
        guard !ids.isEmpty, reachable, let hub = makeProvider(for: config) as? any RunProvider else { return }
        Task {
            for id in ids { _ = try? await hub.cancelRun(id: id) }
        }
    }

    /// "The reply is still being written on home.", under a reply a hub is
    /// writing away from this device, which offers neither Continue nor
    /// Retry: either would start a second reply beside it.
    public func writingLine(for message: Message, in conversation: Conversation) -> String? {
        guard message.isBeingWritten else { return nil }
        return "The reply is still being written on \(provider(for: conversation)?.name ?? "the machine")."
    }
}
