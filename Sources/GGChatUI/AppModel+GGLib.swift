import Foundation
import GGChatCore

/// What a provider's model list last said of its gglib: nothing, as a
/// server that is not gglib and a gglib from before 0.35.0 say, or its
/// version and the features it serves.
enum GGLibAnswer: Equatable {
    case silent
    case server(GGLibServer)
}

// What each server's gglib says of itself beside its model list
// (`GGLibServer`), and what that decides: whether it is sent gglib's own
// keys, whether a reply to it is a run, and whether it has the desk's chats,
// drawing and the status pane. Kept from the last list in memory for as long
// as the app runs, replaced by each list after it, and forgotten when its
// provider is moved or removed. Nothing is guessed from a route that is not
// there: a feature is used only once its gglib has said it serves it.
extension AppModel {
    /// What `providerID`'s gglib said of itself, or nil when its list said
    /// nothing or was never read.
    func gglib(of providerID: UUID) -> GGLibServer? {
        guard case .server(let server)? = gglibAnswers[providerID] else { return nil }
        return server
    }

    /// Whether `config`'s gglib said it serves `feature`. This device's
    /// engine serves none of them.
    func serves(_ feature: GGLibFeature, _ config: ProviderConfig) -> Bool {
        config.kind != .onDevice && gglib(of: config.id)?.serves(feature) == true
    }

    /// Whether `config` is a paired Mac whose list said nothing of its
    /// gglib: one from before 0.35.0, which serves none of the features here
    /// until it is updated.
    func needsUpdating(_ config: ProviderConfig) -> Bool {
        config.isPairedMac && gglibAnswers[config.id] == .silent
    }

    /// Lists `config`'s models when what its gglib serves is not known yet,
    /// so a step that needs it reads it first. A list that fails leaves it
    /// unknown, and the step does without.
    func learnGGLib(_ config: ProviderConfig) async {
        guard config.kind != .onDevice, gglibAnswers[config.id] == nil else { return }
        await listModels(of: config, quietly: true)
    }

    /// Lists `config`'s models, or waits for the list already on its way for
    /// it: the steps a pipe coming up starts each need the list, and ask
    /// once between them. A caller that joins a list keeps its own
    /// `quietly` out of it. A provider whose session is not up is not asked,
    /// as `catchUp` does not ask it: asking raises "not connected yet".
    func listModels(of config: ProviderConfig, quietly: Bool) async {
        if let running = modelListing[config.id] { return await running.value }
        let task = Task {
            guard sessionIsUp(config) else { return }
            await refreshModels(for: config, quietly: quietly)
        }
        modelListing[config.id] = task
        await task.value
        if modelListing[config.id] == task { modelListing[config.id] = nil }
    }

    /// Whether this provider's status pane shows: its gglib serves it.
    public func proxyStatusAvailable(for providerID: UUID) -> Bool {
        providers.first { $0.id == providerID }.map { serves(.status, $0) } ?? false
    }

    /// Whether this provider is known to be gglib: a paired Mac and this
    /// device's engine are, and a server by address is once its list has
    /// said so. Only gglib is asked for progress while the prompt is read,
    /// asked not to think, and sent the tool calls its replies made, and
    /// only its list says which models read images. A server not known to be
    /// gglib is never sent any of them.
    func speaksGGLib(_ config: ProviderConfig) -> Bool {
        switch config.kind {
        case .openAICompatible: gglib(of: config.id) != nil
        case .pipe, .onDevice: true
        }
    }

    /// Whether a reply to this provider is a run (`AppModel+Runs`): its
    /// gglib serves runs. This device's engine streams its replies and keeps
    /// no runs.
    func hasRuns(_ config: ProviderConfig) -> Bool {
        serves(.runs, config)
    }

    /// Whether a conversation on this provider has a Draw switch: gglib's
    /// does, but for this device's engine, which draws nothing. Only a
    /// paired Mac draws; by address the switch says why not
    /// (`needsAPairedMac`), and a Mac that cannot says why
    /// (`drawRefusal`).
    func canDraw(_ config: ProviderConfig) -> Bool {
        switch config.kind {
        case .openAICompatible, .pipe: speaksGGLib(config)
        case .onDevice: false
        }
    }

    /// "home runs gglib 0.35.0", for each provider whose list said its
    /// gglib's version, in the providers' order.
    public var serverGGLibLines: [String] {
        providers.compactMap { config in gglib(of: config.id).map { "\(config.name) runs gglib \($0.version)" } }
    }
}
