import Foundation
import GGChatCore

// Adding, editing and removing a provider, and the models each one lists.
// `AppModel.swift` keeps the state these work on.

/// Why an edit to a provider could not be made.
public enum ProviderEditError: Error, Sendable, Equatable, LocalizedError {
    /// It left the list while its form was open. Worth a sentence rather
    /// than a silent no-op: a re-pairing spends a one-time code before it
    /// gets here, and a form that closed as though it had saved would leave
    /// the user hunting for a machine that is simply no longer listed.
    case noLongerThere

    public var errorDescription: String? {
        switch self {
        case .noLongerThere: "That provider was removed while you were editing it."
        }
    }
}

extension AppModel {
    // MARK: - Providers

    /// Throws rather than reporting, because the form that calls this is a
    /// sheet: an alert raised behind a dismissing sheet is never seen, so the
    /// caller keeps the sheet open and shows the reason in place.
    public func addProvider(_ config: ProviderConfig, credentials: [SecretKind: String]) throws {
        var written: [SecretKind] = []
        do {
            for (kind, secret) in credentials where !secret.isEmpty {
                try secrets.setSecret(secret, kind, for: config.id)
                written.append(kind)
            }
            try store.save(provider: config)
        } catch {
            // Leave nothing half-added: a provider whose token did not save
            // would fail later, further from the cause.
            for kind in written {
                try? secrets.setSecret(nil, kind, for: config.id)
            }
            log.log(.error, "could not add \(config.name): \(error.localizedDescription)")
            throw error
        }
        providers.append(config)
    }

    public func updateProvider(_ config: ProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == config.id }) else { return }
        let previous = providers[index]
        providers[index] = config
        forgetProxyStatus(ifMovedFrom: previous, to: config)
        do {
            try store.save(provider: config)
        } catch {
            report(error)
        }
    }

    /// Re-credentials a provider that is already there, keeping its id.
    ///
    /// Keeping the id is what makes this an edit and not a delete plus a
    /// re-add: a conversation names its provider by that id as a plain
    /// value, and every secret is filed under it, so a new id would orphan
    /// both. A pipe is paired again when its machine stops admitting this
    /// device or has a new ticket, and without this that meant throwing the
    /// provider away and rebuilding it, taking its conversations with it.
    ///
    /// Only the credentials named here are written, and an empty one is
    /// skipped: the form asks for a replacement, not for what is already
    /// stored.
    ///
    /// Throws and puts back what it found, for
    /// ``addProvider(_:credentials:)``'s reason — the form that calls this is
    /// a sheet. Half a new credential beside half an old one is worse than
    /// not editing at all: it is a ticket and a token from two machines.
    public func updateProvider(_ config: ProviderConfig, credentials: [SecretKind: String]) throws {
        guard let index = providers.firstIndex(where: { $0.id == config.id }) else {
            throw ProviderEditError.noLongerThere
        }
        var replacedSecrets: [SecretKind: String?] = [:]
        do {
            for (kind, secret) in credentials where !secret.isEmpty {
                let previousSecret = try secrets.secret(kind, for: config.id)
                replacedSecrets.updateValue(previousSecret, forKey: kind)
                try secrets.setSecret(secret, kind, for: config.id)
            }
            try store.save(provider: config)
        } catch {
            for (kind, previousSecret) in replacedSecrets {
                try? secrets.setSecret(previousSecret, kind, for: config.id)
            }
            log.log(.error, "could not update \(config.name): \(error.localizedDescription)")
            throw error
        }
        let previous = providers[index]
        providers[index] = config
        forgetProxyStatus(ifMovedFrom: previous, to: config)
    }

    /// Forgets a provider: the durable record first, then its credentials.
    ///
    /// The order is the whole of it. Both calls throw, and only one of the
    /// two leftovers is harmless. A row that outlives its credentials is
    /// resurrected by the next ``load()`` as a provider that can never
    /// connect and whose only remaining move is to be deleted again; a
    /// credential that outlives its row is unreachable, because its key is a
    /// provider id nothing holds any more.
    ///
    /// So the record goes first, and if that will not go, nothing else is
    /// touched and the provider goes back where it was taken from.
    ///
    /// The reply in flight through it, streaming or still waiting for its
    /// pipe, is put down as Stop puts it down, and waited for, so what had
    /// arrived is kept before its pipe is hung up. A reply through another
    /// provider goes on.
    public func removeProvider(_ id: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        let removed = providers.remove(at: index)
        do {
            try store.deleteProvider(id: id)
        } catch {
            providers.insert(removed, at: index)
            report(error)
            return
        }
        forgetLastHeard(id)
        // Replies its hub is still writing away from here are given up, and
        // the one being read is put down as Stop puts it down.
        giveUpRuns(through: removed)
        let reply = replyProviderID == id ? streamTask : nil
        reply?.cancel()
        Task {
            await reply?.value
            await disconnectPipe(for: id)
        }
        do {
            try secrets.removeAll(for: id)
        } catch {
            report(error)
        }
    }

    public func provider(for conversation: Conversation) -> ProviderConfig? {
        providers.first { $0.id == conversation.providerID }
    }

    // MARK: - Providers and models

    func makeProvider(for config: ProviderConfig) -> (any Provider)? {
        switch config.kind {
        case .openAICompatible(let baseURL):
            let apiKey = try? secrets.secret(.apiKey, for: config.id)
            return registry.makeProvider(baseURL: baseURL, apiKey: apiKey, log: log)
        case .pipe:
            return makePipeProvider(for: config)
        }
    }

    public func models(for providerID: UUID) -> [ModelInfo] {
        modelsByProvider[providerID] ?? []
    }

    /// Lists the provider's models and remembers them. Errors surface as
    /// the server's sentence.
    ///
    /// Except when the task asking was called off. The request then fails
    /// because it was, and says so as "Could not reach the server:
    /// cancelled", which is about nothing the person did or can do. That
    /// alert is what a cancelled view task used to put in front of them
    /// (#126).
    ///
    /// - Parameters:
    ///   - config: the provider whose models to list.
    ///   - quietly: logs a failure instead of raising the alert, for a
    ///     refresh nobody asked for.
    public func refreshModels(for config: ProviderConfig, quietly: Bool = false) async {
        guard let provider = makeProvider(for: config) else { return }
        do {
            let models = try await provider.models()
            heard(config.id)
            modelsByProvider[config.id] = models
            if config.defaultModel == nil, let first = models.first {
                var updated = config
                updated.defaultModel = first.id
                updateProvider(updated)
            }
        } catch {
            note(error, from: config.id)
            if Task.isCancelled {
                log.log(.info, "listing models for \(config.name) was called off")
                return
            }
            if quietly {
                log.log(.info, "listing models for \(config.name) failed: \(error.localizedDescription)")
                return
            }
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
