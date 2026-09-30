import Foundation
import GGChatCore

extension AppModel {
    public var isStreaming: Bool {
        liveReply != nil
    }

    public func isStreaming(_ conversationID: UUID) -> Bool {
        liveReply?.conversationID == conversationID
    }

    /// The last failure of a stream in this conversation, as the provider
    /// reported it, for as long as the app runs. What the transcript draws is
    /// the `failure` kept on the message that ended the turn, which is what
    /// outlives a relaunch.
    public func streamError(for conversationID: UUID) -> ProviderError? {
        streamErrors[conversationID]
    }

    /// Appends the user's message and streams the reply.
    @discardableResult
    public func send(_ text: String) -> Task<Void, Never>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var conversation = selectedConversation, !isStreaming,
            !conversation.messages.contains(where: \.isBeingWritten)
        else { return nil }
        let stamp = now()
        conversation.messages.append(Message(role: .user, content: trimmed, createdAt: stamp))
        conversation.updatedAt = stamp
        update(conversation)
        return stream(conversation, continuing: nil)
    }

    /// Re-sends the conversation with its partial reply as the last message,
    /// so the model carries on from where it stopped. See ADR 0002.
    @discardableResult
    public func continueReply() -> Task<Void, Never>? {
        guard let conversation = selectedConversation, !isStreaming,
            let last = conversation.messages.last, last.role == .assistant, last.isPartial, !last.isBeingWritten
        else { return nil }
        diagnostics.recordContinue()
        return stream(conversation, continuing: last.id)
    }

    /// Asks the last question again. The last message is the user's and
    /// nothing is under it: the request was refused before its first token,
    /// or stopped, or the app went to the background first. There is no
    /// partial to keep and nothing to continue, so the question itself goes
    /// again, and no second copy of it is added.
    ///
    /// Nothing is sent until the user presses it, which is ADR 0002's rule,
    /// and there is no reply here for that rule to protect. It is not counted
    /// with Continue, whose counter asks whether a half-reply is worth
    /// resuming; this asks whether an unanswered question is worth asking
    /// again.
    ///
    /// A refusal on the question is cleared only once the request is on its
    /// way, or waiting for its pipe, so a conversation whose provider has
    /// gone, or that has no model, keeps its sentence and says why nothing
    /// was sent.
    @discardableResult
    public func retry() -> Task<Void, Never>? {
        guard var conversation = selectedConversation, !isStreaming,
            let last = conversation.messages.indices.last, conversation.messages[last].role == .user
        else { return nil }
        conversation.messages[last].failure = nil
        guard let task = stream(conversation, continuing: nil) else { return nil }
        update(conversation)
        return task
    }

    /// Puts the reply in flight down. A run is cancelled on its hub, where
    /// the background only walks away from it; the reading task tells the
    /// two apart by `LiveReply.detaching`, which only the background sets.
    public func stop() {
        liveReply?.stoppedHere = true
        streamTask?.cancel()
    }

    private func stream(_ conversation: Conversation, continuing: UUID?) -> Task<Void, Never>? {
        guard let config = provider(for: conversation) else {
            lastError = "This conversation has no provider. Add one, then pick it."
            return nil
        }
        guard let modelID = conversation.model ?? config.defaultModel else {
            lastError = "Pick a model first."
            return nil
        }
        // A pipe that is not connected is waited for, not refused.
        let waits = config.isPipe && pipeStatuses[config.id]?.isConnected != true
        let ready = waits ? nil : makeProvider(for: config)
        if !waits, ready == nil { return nil }
        streamErrors[conversation.id] = nil
        let live = LiveReply(conversationID: conversation.id, continuingMessageID: continuing)
        live.waitingFor = waits ? config.id : nil
        liveReply = live
        let request = ChatRequest(
            model: modelID, messages: conversation.requestMessages, returnProgress: asksForProgress(config))
        let task = Task { [weak self] in
            var connected = ready
            if connected == nil { connected = await self?.providerOnceConnected(config, for: live) }
            guard let provider = connected else { return }
            if let hub = self?.runHub(provider, for: config) {
                await self?.startRun(request, on: hub, for: config, live: live)
            } else {
                await self?.streamChat(request, on: provider, live: live)
            }
        }
        streamTask = task
        return task
    }

    /// Streams the reply from `chat/completions`, the way every reply went
    /// before runs, and every reply to a hub without them still goes.
    func streamChat(_ request: ChatRequest, on provider: any Provider, live: LiveReply) async {
        var finished = false
        for await event in provider.stream(request) {
            if case .finished = event { finished = true } else { apply(event, to: live) }
        }
        let cancelled = Task.isCancelled
        finish(live, finished: finished && !cancelled, cancelled: cancelled)
    }

    /// Adds one event to the reply in flight. The end of a reply is not one of
    /// them: the chat route and a run each say it in their own way.
    func apply(_ event: ChatEvent, to live: LiveReply) {
        switch event {
        case .delta(let text): live.content += text
        case .reasoning(let text): live.reasoning += text
        case .progress(let progress): live.progress = progress
        case .error(let error): live.error = error
        case .tool, .finished: break
        }
    }

    /// The provider to stream through once the pipe is connected, or nil when
    /// the wait ended another way, in which case the reply is finished here:
    /// as Stop finishes it, or with the refused dial's sentence.
    private func providerOnceConnected(_ config: ProviderConfig, for live: LiveReply) async -> (any Provider)? {
        switch await waitForPipe(config) {
        case .connected(let provider):
            live.waitingFor = nil
            return provider
        case .refused(let failure):
            finish(live, finished: false, cancelled: false, refusal: failure)
        case .calledOff:
            finish(live, finished: false, cancelled: true)
        }
        return nil
    }

    /// What to do about a failure, from the provider behind this
    /// conversation, or nil when the sentence and the line under it already
    /// say it. Only `invalid_api_key` has any so far. Its remedy is a new key,
    /// and where one comes from depends on the kind of provider: a pipe pairs
    /// again, a server takes its key from whoever runs it. Core cannot tell
    /// the two apart, and a server's user must never be told to run a gglib
    /// command.
    ///
    /// Plain text rather than markdown, because it carries the provider's
    /// name, and a name is not markup. It says "try again" rather than naming
    /// a button, because it is drawn under a partial reply too, where the
    /// button is Continue.
    public func advice(for failure: Failure, in conversation: Conversation) -> String? {
        guard failure.code == ProviderError.Code.invalidAPIKey.rawValue,
            let config = provider(for: conversation)
        else { return nil }
        switch config.kind {
        case .pipe:
            return "If a key changed there, it reaches the tunnel within seconds, so try again first. "
                + "If it still refuses, run \u{201C}gglib remote invite\u{201D} on that machine and paste what it "
                + "shows under Providers › \(config.name) › Pairing string."
        case .openAICompatible:
            return "Check the API key under Providers › \(config.name)."
        }
    }
}
