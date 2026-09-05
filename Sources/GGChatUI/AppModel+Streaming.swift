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

    /// The last failure of a stream in this conversation, shown under the
    /// partial reply as the server's own sentence.
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
            self?.finish(live, finished: finished && !Task.isCancelled)
        }
        streamTask = task
        return task
    }

    private func finish(_ live: LiveReply, finished: Bool) {
        defer {
            liveReply = nil
            streamTask = nil
        }
        guard var conversation = conversations.first(where: { $0.id == live.conversationID }) else { return }
        let stamp = now()
        if let continuingID = live.continuingMessageID,
            let index = conversation.messages.firstIndex(where: { $0.id == continuingID })
        {
            conversation.messages[index].content += live.content
            if !live.reasoning.isEmpty {
                conversation.messages[index].reasoning = (conversation.messages[index].reasoning ?? "") + live.reasoning
            }
            conversation.messages[index].isPartial = !finished
        } else if !live.content.isEmpty || !live.reasoning.isEmpty || finished {
            conversation.messages.append(
                Message(
                    role: .assistant, content: live.content,
                    reasoning: live.reasoning.isEmpty ? nil : live.reasoning,
                    isPartial: !finished, createdAt: stamp))
        }
        conversation.updatedAt = stamp
        diagnostics.recordStreamEnd(with: live.error, at: stamp)
        if let error = live.error {
            streamErrors[conversation.id] = error
            log.log(.error, "stream ended with \(error.code ?? "no code"): \(error.whereToLook)")
        }
        update(conversation)
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
