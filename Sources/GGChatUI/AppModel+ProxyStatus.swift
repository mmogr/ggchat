import Foundation
import GGChatCore

extension AppModel {
    /// Forgets what a provider's server said of itself when an edit moves it
    /// to another address or machine: its list of models and what its
    /// gglib serves, which the next catch-up lists again rather than wait
    /// for a list on its way from the old one, with the default
    /// chosen from that (`forgettingTheDefault`), and what it can draw. The
    /// image model and the servers each of its conversations chose go too,
    /// and the model where its list named models by gglib's ids
    /// (`keysByID`): an id names a model or a server on the old machine
    /// alone, and re-pairing is such a move.
    func forgetTheOldMachine(ifMovedFrom previous: ProviderConfig, to config: ProviderConfig) {
        guard previous.kind != config.kind else { return }
        let keyedByID = keysByID(config.id)
        modelsByProvider[config.id] = nil
        gglibAnswers[config.id] = nil
        modelListing[config.id] = nil
        drawings[config.id] = nil
        forgetMachineChoices(on: config.id, models: keyedByID)
    }

    /// `config` as an edit leaves it: one that moves it to another machine
    /// forgets its default model where the old machine's list named it by
    /// gglib's id (`keysByID`), and the next list chooses one
    /// (`refreshModels`). A default named by its name is kept.
    func forgettingTheDefault(of config: ProviderConfig, ifMovedFrom previous: ProviderConfig) -> ProviderConfig {
        guard previous.kind != config.kind, keysByID(config.id) else { return config }
        var moved = config
        moved.defaultModel = nil
        return moved
    }

    /// Forgets every image model and server chosen on a provider, and with
    /// `models` every model, when it is moved to another machine: an id
    /// names a model or a server on the old one alone, so a conversation
    /// runs on the new machine's default (`model(for:)`). One write for each
    /// conversation that chose any of them, and none for one that chose none.
    func forgetMachineChoices(on providerID: UUID, models: Bool) {
        imageChoiceAnswers[providerID] = nil
        for var conversation in conversations where conversation.providerID == providerID {
            let model = models ? nil : conversation.model
            guard model != conversation.model || conversation.imageModelID != nil || !conversation.toolChoice.isDefault
            else { continue }
            conversation.model = model
            conversation.imageModelID = nil
            conversation.toolChoice = ToolChoice()
            update(conversation)
        }
        if openedHubChat?.providerID == providerID { openedHubChat?.imageModel = nil }
    }

    /// The live snapshot stream, for the pane while it is open.
    public func proxyStatusStream(for config: ProviderConfig) -> AsyncThrowingStream<ProxyStatus, any Error>? {
        (makeProvider(for: config) as? OpenAICompatibleProvider)?.proxyStatusStream()
    }
}
