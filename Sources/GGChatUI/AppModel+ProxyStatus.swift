import Foundation
import GGChatCore

extension AppModel {
    /// Whether this provider answers `GET /v1/proxy/status`. Unknown until
    /// probed; false hides the pane.
    public func proxyStatusAvailable(for providerID: UUID) -> Bool {
        proxyStatusAvailability[providerID] ?? false
    }

    /// Whether this provider is known to be gglib: a paired Mac is, and a
    /// server by address is once it has answered the status probe. Only
    /// gglib is asked for progress while the prompt is read, asked not to
    /// think, and sent the tool calls its replies made, and only its list
    /// says which models read images. A server not known to be gglib is
    /// never sent any of them.
    func speaksGGLib(_ config: ProviderConfig) -> Bool {
        switch config.kind {
        case .openAICompatible: proxyStatusAvailable(for: config.id)
        case .pipe: true
        }
    }

    /// Whether a reply to this provider is a run (`AppModel+Runs`): gglib's
    /// is, until it has answered as one without runs.
    func hasRuns(_ config: ProviderConfig) -> Bool {
        speaksGGLib(config) && !providersWithoutRuns.contains(config.id)
    }

    /// Whether a conversation on this provider has a Draw switch: gglib's
    /// does. Only a paired Mac draws; by address the switch says why not
    /// (`needsAPairedMac`).
    func canDraw(_ config: ProviderConfig) -> Bool {
        speaksGGLib(config)
    }

    /// Forgets the probe's answer when an edit moves a provider to another
    /// address or machine, as `setPipeStatus` does when a pipe comes up. The
    /// answer was about the old one, and a server that is not gglib must not
    /// be asked for progress. The image model and the servers each of its
    /// conversations chose go too: an id names a model or a server on the
    /// old machine alone, and re-pairing is such a move. The generation drops
    /// a probe still in flight.
    func forgetProxyStatus(ifMovedFrom previous: ProviderConfig, to config: ProviderConfig) {
        guard previous.kind != config.kind else { return }
        proxyStatusAvailability[config.id] = nil
        providersWithoutRuns.remove(config.id)
        drawings[config.id] = nil
        forgetMachineChoices(on: config.id)
        probeGeneration[config.id] = (probeGeneration[config.id] ?? 0) + 1
    }

    /// Forgets every image model and every server chosen on a provider,
    /// when it is moved to another machine: an id names a model or a server
    /// on the old one alone. One write for each conversation that chose
    /// either, and none for one that chose neither.
    func forgetMachineChoices(on providerID: UUID) {
        imageChoiceAnswers[providerID] = nil
        for var conversation in conversations where conversation.providerID == providerID {
            guard conversation.imageModelID != nil || !conversation.toolChoice.isDefault else { continue }
            conversation.imageModelID = nil
            conversation.toolChoice = ToolChoice()
            update(conversation)
        }
        if openedHubChat?.providerID == providerID { openedHubChat?.imageModel = nil }
    }

    /// Asks once per provider, and again each time its pipe comes up. A 404
    /// or a non-server provider means "no pane", kept until then. A request
    /// that fails, whether by transport, an error status or a body that does
    /// not decode, keeps nothing, so the next catch-up asks again. Nothing is
    /// reported to the user.
    ///
    /// A pipe with no session yet is not asked and nothing is kept for it:
    /// asking through `makeProvider` then raises its "not connected yet"
    /// alert. `setPipeStatus` forgets the answer when the pipe comes up, and
    /// asks again for a provider a conversation has been opened on.
    public func probeProxyStatus(for config: ProviderConfig) async {
        if proxyStatusAvailability[config.id] != nil { return }
        // Only a server is asked: a paired Mac, or one reached by its address.
        guard config.isPairedMac || !config.hasSession else { return }
        if config.hasSession, pipeSessions[config.id] == nil { return }
        // A caller can hold a config it read before an await. If an edit has
        // moved the provider since, the old address is not asked, because its
        // answer would be kept for the new one.
        guard providers.first(where: { $0.id == config.id })?.kind == config.kind else { return }
        guard let provider = makeProvider(for: config) as? OpenAICompatibleProvider else {
            proxyStatusAvailability[config.id] = false
            return
        }
        let generation = (probeGeneration[config.id] ?? 0) + 1
        probeGeneration[config.id] = generation
        // Any answer, a 404 included, is the machine heard.
        let snapshot: ProxyStatus?
        do {
            snapshot = try await provider.proxyStatus()
            heard(config.id)
        } catch {
            note(error, from: config.id)
            return
        }
        // Kept only if nothing moved this probe on while it waited. A pipe
        // coming up moves it on, and so does a newer probe. A cancelled
        // caller is checked as well, but cancellation can arrive after the
        // answer is already in, and an answer from before the reconnect would
        // then be kept until the next one. The generation does not depend on
        // that timing.
        guard probeGeneration[config.id] == generation, !Task.isCancelled else { return }
        let available = snapshot != nil
        proxyStatusAvailability[config.id] = available
        log.log(.info, "proxy status \(available ? "available" : "absent") for \(config.name)")
    }

    /// The live snapshot stream, for the pane while it is open.
    public func proxyStatusStream(for config: ProviderConfig) -> AsyncThrowingStream<ProxyStatus, any Error>? {
        (makeProvider(for: config) as? OpenAICompatibleProvider)?.proxyStatusStream()
    }
}
