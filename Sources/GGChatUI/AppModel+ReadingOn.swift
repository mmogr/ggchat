import Foundation
import GGChatCore

// Reading on from a reply a hub went on writing while nobody read it, and
// the ways out of waiting for one: Stop, and removing its provider.
extension AppModel {
    /// How long to wait before each read-on after one that got nothing, in a
    /// row. After the last, the reply waits for the next return, launch or
    /// pipe coming up.
    static let readOnDelays: [Duration] = [.seconds(2), .seconds(10), .seconds(30)]

    /// Walks away from the run, keeping what arrived with its id and cursor.
    /// A reading that got somewhere reads on at once; one that got nothing
    /// reads on after a pause, a few times, so a hub that cannot be reached
    /// is not asked again and again.
    func walkAway(_ live: LiveReply, readAny: Bool) {
        finish(live, finished: false, cancelled: true, keepsRun: true)
        let conversation = conversations.first { $0.id == live.conversationID }
        guard let kept = conversation?.messages.last(where: \.isBeingWritten)?.id else { return }
        if readAny {
            readOnAttempts[kept] = nil
            return readOnDetachedRuns(preferring: kept)
        }
        readOnAfterAPause(kept) { $0.readOnDetachedRuns(preferring: kept) }
    }

    /// Reads on after the next pause in a row for `key`, or never once the
    /// pauses are spent, so a hub that cannot be reached is not asked again
    /// and again. Shared by this device's replies and a Mac's chat's.
    func readOnAfterAPause(_ key: UUID, _ readOn: @escaping (AppModel) -> Void) {
        let attempt = readOnAttempts[key] ?? 0
        guard attempt < Self.readOnDelays.count else { return }
        readOnAttempts[key] = attempt + 1
        Task { [weak self, sleeper] in
            try? await sleeper.sleep(for: Self.readOnDelays[attempt])
            guard let self else { return }
            readOn(self)
        }
    }

    /// Coming back, and at launch: dials the pipes behind replies still being
    /// written, and reads on through the hubs that can be reached now. A pipe
    /// reads on once it comes up; see `setPipeStatus`.
    func resumeRuns() {
        readOnAttempts = [:]
        let pipes = Set(conversations.filter { $0.messages.contains(where: \.isBeingWritten) }.compactMap(\.providerID))
        for config in providers where config.isPipe && pipes.contains(config.id) && pipeSessions[config.id] == nil {
            Task { await connectPipe(for: config, quietly: true) }
        }
        readOnDetachedRuns()
        readOnHubReply()
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
    /// not when its hub cannot be reached now. A run whose `PUT` was never
    /// answered is asked for again under its id first.
    private func readOn(_ message: Message, in conversation: Conversation) -> Bool {
        let live = LiveReply(conversationID: conversation.id, continuingMessageID: message.id)
        live.runID = message.runID
        live.cursor = message.runCursor ?? 0
        live.started = message.runCursor != nil
        live.model = conversation.model ?? provider(for: conversation)?.defaultModel
        guard let config = provider(for: conversation) else {
            // Its provider is gone, and the hub with it.
            giveUp(live, saying: "is no longer a provider here, so the rest of this reply cannot be read.")
            return false
        }
        guard let hub = reachableHub(for: config) else { return false }
        var request: ChatRequest?
        do {
            request = live.started ? nil : try sentRequest(for: message, in: conversation, config: config)
        } catch {
            // Sent again without its image it would be another question, so
            // the reply is given up with the reason, and Retry asks again.
            finish(live, finished: false, cancelled: false, refusal: error.failure)
            return false
        }
        if !live.started, request == nil { return false }
        liveReply = live
        streamTask = Task { [weak self] in
            if let request {
                await self?.putRun(request, on: hub, for: config, live: live)
            } else {
                await self?.readRun(on: hub, live: live)
            }
        }
        return true
    }

    /// The request a run was started with, built again from the conversation:
    /// the turns before the reply, and the reply itself when it was a
    /// Continue's partial. Nothing had been read into it, so it is as sent.
    private func sentRequest(
        for message: Message, in conversation: Conversation, config: ProviderConfig
    ) throws(ImageUnavailable) -> ChatRequest? {
        guard let modelID = conversation.model ?? config.defaultModel,
            let index = conversation.messages.firstIndex(where: { $0.id == message.id })
        else { return nil }
        var sent = conversation
        sent.messages = Array(conversation.messages[..<index]) + (message.content.isEmpty ? [] : [message])
        return try chatRequest(model: modelID, messages: sent.requestMessages, for: config)
    }

    /// The provider as a run hub, when it can be reached without dialling.
    func reachableHub(for config: ProviderConfig) -> (any RunProvider)? {
        let connected = pipeSessions[config.id] != nil && pipeStatuses[config.id]?.isConnected == true
        guard !config.isPipe || connected else { return nil }
        return makeProvider(for: config) as? any RunProvider
    }

    // MARK: - Ways out

    /// Stop, under a reply a hub is still writing away from this device. The
    /// run is cancelled when its hub can be reached, and given up here either
    /// way, so the conversation is free again: what arrived stays, with
    /// Continue, and an empty reply leaves the question with Retry.
    public func stopWriting(_ messageID: UUID) {
        if liveReply?.continuingMessageID == messageID { return stop() }
        guard let conversation = conversations.first(where: { $0.messages.contains { $0.id == messageID } }),
            let message = conversation.messages.first(where: { $0.id == messageID }), let id = message.runID
        else { return }
        if let config = provider(for: conversation), let hub = reachableHub(for: config) { cancelRun(id, on: hub) }
        letGo(message, in: conversation, stoppedHere: true)
    }

    /// Gives up, here, the runs still writing replies through a provider that
    /// is being removed, cancelling them first while its hub can be reached.
    func giveUpRuns(through config: ProviderConfig) {
        let hub = reachableHub(for: config)
        for conversation in conversations where conversation.providerID == config.id {
            for message in conversation.messages where message.isBeingWritten {
                guard liveReply?.continuingMessageID != message.id, let id = message.runID else { continue }
                if let hub { cancelRun(id, on: hub) }
                letGo(message, in: conversation)
            }
        }
    }

    /// Cancels, on their hubs, the runs still writing replies in a
    /// conversation that is going away.
    func stopDetachedRuns(in conversation: Conversation) {
        guard let config = provider(for: conversation), let hub = reachableHub(for: config) else { return }
        for id in conversation.messages.compactMap(\.runID) { cancelRun(id, on: hub) }
    }

    /// Ends a reply nobody is reading as a stopped one, without its run.
    private func letGo(_ message: Message, in conversation: Conversation, stoppedHere: Bool = false) {
        readOnAttempts[message.id] = nil
        let live = LiveReply(conversationID: conversation.id, continuingMessageID: message.id)
        live.stoppedHere = stoppedHere
        finish(live, finished: false, cancelled: true)
    }

    /// "The reply is still being written on home.", under a reply a hub is
    /// writing away from this device, which offers Stop and neither Continue
    /// nor Retry: either would start a second reply beside it.
    public func writingLine(for message: Message, in conversation: Conversation) -> String? {
        guard message.isBeingWritten else { return nil }
        return "The reply is still being written on \(provider(for: conversation)?.name ?? "the machine")."
    }
}
