import Foundation
import GGChatCore
import Observation

/// The reply being streamed right now. Only the last row observes it, so a
/// token touches one view and the transcript above it never re-lays out.
@Observable
public final class LiveReply {
    public let conversationID: UUID
    /// Set when Continue is streaming into an existing partial message.
    public let continuingMessageID: UUID?
    public var content = ""
    public var reasoning = ""
    public var error: ProviderError?

    init(conversationID: UUID, continuingMessageID: UUID?) {
        self.conversationID = conversationID
        self.continuingMessageID = continuingMessageID
    }
}

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
        guard !trimmed.isEmpty, var conversation = selectedConversation, !isStreaming else { return nil }
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
            let last = conversation.messages.last, last.role == .assistant, last.isPartial
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
    /// way, so a conversation whose provider has gone, or that has no model,
    /// keeps its sentence and says why nothing was sent.
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

    public func stop() {
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
        guard let provider = makeProvider(for: config) else { return nil }
        streamErrors[conversation.id] = nil
        let live = LiveReply(conversationID: conversation.id, continuingMessageID: continuing)
        liveReply = live
        let request = ChatRequest(model: modelID, messages: conversation.messages)
        let task = Task { [weak self] in
            var finished = false
            for await event in provider.stream(request) {
                switch event {
                case .delta(let text): live.content += text
                case .reasoning(let text): live.reasoning += text
                case .finished: finished = true
                case .error(let error): live.error = error
                }
            }
            let cancelled = Task.isCancelled
            self?.finish(live, finished: finished && !cancelled, cancelled: cancelled)
        }
        streamTask = task
        return task
    }

    private func finish(_ live: LiveReply, finished: Bool, cancelled: Bool) {
        defer {
            liveReply = nil
            streamTask = nil
        }
        guard var conversation = conversations.first(where: { $0.id == live.conversationID }) else { return }
        let stamp = now()
        // A stop or a background is not a failure, however the provider put
        // it: a cancelled request can surface as a transport error, and
        // whether that arrives before the stream ends is a race. Nor is it a
        // transport error after a resume, for the diagnostics below.
        let error = cancelled ? nil : live.error
        let failure = error.map(Failure.init)
        if let continuingID = live.continuingMessageID,
            let index = conversation.messages.firstIndex(where: { $0.id == continuingID })
        {
            conversation.messages[index].content += live.content
            if !live.reasoning.isEmpty {
                conversation.messages[index].reasoning = (conversation.messages[index].reasoning ?? "") + live.reasoning
            }
            conversation.messages[index].isPartial = !finished
            conversation.messages[index].failure = failure
        } else if !live.content.isEmpty || !live.reasoning.isEmpty || finished {
            conversation.messages.append(
                Message(
                    role: .assistant, content: live.content,
                    reasoning: live.reasoning.isEmpty ? nil : live.reasoning,
                    isPartial: !finished, failure: failure, createdAt: stamp))
        } else if let failure, let last = conversation.messages.indices.last,
            conversation.messages[last].role == .user
        {
            // Nothing arrived and something said why. With no reply to put
            // the sentence under, it goes on the question.
            conversation.messages[last].failure = failure
        }
        conversation.updatedAt = stamp
        diagnostics.recordStreamEnd(with: error, at: stamp)
        if let error {
            streamErrors[conversation.id] = error
            log.log(.error, "stream ended with \(error.code ?? "no code"): \(error.whereToLook)")
        }
        update(conversation)
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

    // MARK: - Providers and models

    func makeProvider(for config: ProviderConfig) -> (any Provider)? {
        switch config.kind {
        case .openAICompatible(let baseURL):
            let key = try? secrets.secret(.apiKey, for: config.id)
            return registry.makeProvider(baseURL: baseURL, apiKey: key, log: log)
        case .pipe:
            return makePipeProvider(for: config)
        }
    }

    public func models(for providerID: UUID) -> [ModelInfo] {
        modelsByProvider[providerID] ?? []
    }

    /// Lists the provider's models and remembers them. Errors surface as
    /// the server's sentence.
    public func refreshModels(for config: ProviderConfig) async {
        guard let provider = makeProvider(for: config) else { return }
        do {
            let models = try await provider.models()
            modelsByProvider[config.id] = models
            if config.defaultModel == nil, let first = models.first {
                var updated = config
                updated.defaultModel = first.id
                updateProvider(updated)
            }
        } catch {
            report(error)
        }
    }

    public func select(model modelID: String, for conversationID: UUID) {
        guard var conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        conversation.model = modelID
        update(conversation)
        if var config = provider(for: conversation) {
            config.defaultModel = modelID
            updateProvider(config)
        }
    }

    /// The status of the pipe behind this conversation, or nil for a server
    /// added by address.
    public func pipeStatus(for conversation: Conversation) -> PipeStatus? {
        guard let config = provider(for: conversation), config.isPipe else { return nil }
        return pipeStatuses[config.id]
    }
}
