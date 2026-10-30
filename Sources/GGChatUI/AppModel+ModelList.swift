import Foundation
import GGChatCore

// The model list under the composer's model pill: every provider's models in
// one list, a section each, in the order the providers are listed, and a
// pick that moves the conversation when the model is on another provider.
// The view filters and searches with `ModelList.make` and computes nothing
// else.
extension AppModel {
    /// The list for `conversation`, filtered to one provider or none and
    /// searched for `query`.
    public func modelList(
        for conversation: Conversation, filter: UUID?, query: String, locale: Locale, calendar: Calendar
    ) -> ModelList {
        ModelList.make(
            modelListSections(for: conversation, locale: locale, calendar: calendar), filter: filter, query: query)
    }

    /// A section for each provider, in the providers' order, which is the
    /// Providers screen's and the chips': a move does not reorder the list
    /// under the person's finger. The conversation's model on its own
    /// provider is ticked.
    func modelListSections(for conversation: Conversation, locale: Locale, calendar: Calendar) -> [ModelListSection] {
        providers.map { config in
            let ownModel = config.id == conversation.providerID ? conversation.model ?? config.defaultModel : nil
            let (listed, rows) = listedRows(of: config)
            let down = config.isPipe && pipeStatuses[config.id]?.isConnected != true
            return ModelListSection(
                provider: config,
                state: listState(
                    of: config, using: ownModel ?? config.defaultModel, locale: locale, calendar: calendar),
                rows: rows.map { ModelListRow(modelID: $0.id, detail: $0.detail, isCurrent: $0.id == ownModel) },
                isListed: listed,
                isStale: listed && down,
                moves: config.id != conversation.providerID,
                offersConnect: !listed && down && canReconnect(config.id))
        }
    }

    /// Whether `config` has listed its models, and the ones that chat with
    /// their detail lines. This iPhone's are the models installed on it,
    /// which the library reads without the engine: the engine starts only
    /// when a conversation on it opens or sends, and a model it has not
    /// listed yet is still one it can load by name. Its line is the
    /// engine's description once the engine has listed the model, and the
    /// model's size until then. Any other provider's are what it last
    /// listed while the app has run.
    private func listedRows(of config: ProviderConfig) -> (Bool, [(id: String, detail: String?)]) {
        let listed = modelsByProvider[config.id]
        if config.kind == .onDevice, let installed = onDevice.installed {
            let rows = installed.filter { ModelInfo(id: $0.name, capabilities: $0.capabilities).chats }.map { item in
                let detail = listed?.first { $0.id == item.name }?.detailLine ?? Sizes.download(item.bytes)
                return (id: item.name, detail: Optional(detail))
            }
            return (true, rows)
        }
        return (listed != nil, chatModels(for: config.id).map { (id: $0.id, detail: $0.detailLine) })
    }

    /// The few words beside a provider's name: how the engine is with the
    /// model a conversation there would use, how a pipe is or when its
    /// machine was last heard, and nothing for a server by address.
    private func listState(
        of config: ProviderConfig, using modelID: String?, locale: Locale, calendar: Calendar
    )
        -> String?
    {
        switch config.kind {
        case .openAICompatible:
            return nil
        case .onDevice:
            guard engine.isAvailable else { return nil }
            return switch modelState(of: modelID) {
            case .notLoaded: "not loaded"
            case .loading(let fraction): "loading \(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
            case .ready: "ready"
            case .failed: "could not load"
            case .tooBig: "too big"
            }
        case .pipe:
            return switch pipeStatuses[config.id] {
            case .direct?, .relayed?: "connected"
            case .idle?: "connecting"
            case .closed?, nil: lastHeardLine(for: config.id, locale: locale, calendar: calendar)
            }
        }
    }

    /// Picks `modelID` on `providerID` for the conversation. On its own
    /// provider that is choosing the model; on another it is moving there
    /// with that model, as choosing the provider and then the model would:
    /// the Thinking choice, the image model and the servers picked go with
    /// the provider left, and nothing moves while a reply is in flight.
    public func pick(model modelID: String, on providerID: UUID, for conversationID: UUID) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        if conversation.providerID != providerID {
            select(provider: providerID, for: conversationID)
            guard conversations.first(where: { $0.id == conversationID })?.providerID == providerID else { return }
        }
        select(model: modelID, for: conversationID)
    }

    /// Dials a pipe the list has nothing from, as the status pill's
    /// Reconnect does, because the person pressed Connect: a dial they asked
    /// for, which says why if it fails. The provider is followed from here,
    /// so its models are listed as its pipe comes up (`setPipeStatus`).
    /// Returns the dial, so a test can wait on it; nil where there is
    /// nothing to dial or a dial is already in flight.
    @discardableResult
    public func connect(fromTheList providerID: UUID) -> Task<Void, Never>? {
        guard let config = providers.first(where: { $0.id == providerID }), config.isPipe, canReconnect(providerID)
        else { return nil }
        followed.insert(providerID)
        return Task { await reconnectPipe(for: config) }
    }

    /// Lists every provider's models again as the list opens, quietly, and
    /// reads what is installed on this iPhone. Only a provider whose session
    /// is up is asked (`sessionIsUp`): no pipe is dialled and no engine
    /// served to fill a list, so a pipe that is down keeps the models it
    /// listed last, dimmed, and This iPhone's come from its library.
    /// Returns the work, so a test can wait on it; nothing the view does
    /// calls it off.
    @discardableResult
    public func relistModels() -> Task<Void, Never> {
        let configs = providers
        return Task {
            await withTaskGroup(of: Void.self) { group in
                for config in configs {
                    if config.kind == .onDevice { group.addTask { await self.refreshInstalled() } }
                    if sessionIsUp(config) { group.addTask { await self.refreshModels(for: config, quietly: true) } }
                }
            }
        }
    }
}
