import Foundation
import GGChatCore

extension AppModel {
    /// Whether this provider answers `GET /v1/proxy/status`. Unknown until
    /// probed; false hides the pane.
    public func proxyStatusAvailable(for providerID: UUID) -> Bool {
        proxyStatusAvailability[providerID] ?? false
    }

    /// Whether a chat request to this provider asks for progress while the
    /// prompt is read. Only gglib is asked: a pipe, or a server that answered
    /// the status probe. A server not known to be gglib is never sent it.
    func asksForProgress(_ config: ProviderConfig) -> Bool {
        config.isPipe || proxyStatusAvailable(for: config.id)
    }

    /// Forgets the probe's answer when an edit moves a provider to another
    /// address or machine, as `setPipeStatus` does when a pipe comes up. The
    /// answer was about the old one, and a server that is not gglib must not
    /// be asked for progress. The generation drops a probe still in flight.
    func forgetProxyStatus(ifMovedFrom previous: ProviderConfig, to config: ProviderConfig) {
        guard previous.kind != config.kind else { return }
        proxyStatusAvailability[config.id] = nil
        providersWithoutRuns.remove(config.id)
        probeGeneration[config.id] = (probeGeneration[config.id] ?? 0) + 1
    }

    /// Asks once per provider, and again each time its pipe comes up. A 404,
    /// a transport failure or a non-server provider all mean "no pane";
    /// nothing is reported to the user.
    ///
    /// A pipe with no session yet is not asked and nothing is kept for it:
    /// asking through `makeProvider` then raises its "not connected yet"
    /// alert. `setPipeStatus` forgets the answer when the pipe comes up, and
    /// asks again for a provider a conversation has been opened on.
    public func probeProxyStatus(for config: ProviderConfig) async {
        if proxyStatusAvailability[config.id] != nil { return }
        if config.isPipe, pipeSessions[config.id] == nil { return }
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
        let snapshot: ProxyStatus??
        do {
            snapshot = try await provider.proxyStatus()
            heard(config.id)
        } catch {
            snapshot = nil
            note(error, from: config.id)
        }
        // Kept only if nothing moved this probe on while it waited. A pipe
        // coming up moves it on, and so does a newer probe. A cancelled
        // caller is checked as well, but cancellation can arrive after the
        // answer is already in, and an answer from before the reconnect would
        // then be kept until the next one. The generation does not depend on
        // that timing.
        guard probeGeneration[config.id] == generation, !Task.isCancelled else { return }
        let available = snapshot.flatMap { $0 } != nil
        proxyStatusAvailability[config.id] = available
        log.log(.info, "proxy status \(available ? "available" : "absent") for \(config.name)")
    }

    /// The live snapshot stream, for the pane while it is open.
    public func proxyStatusStream(for config: ProviderConfig) -> AsyncThrowingStream<ProxyStatus, any Error>? {
        (makeProvider(for: config) as? OpenAICompatibleProvider)?.proxyStatusStream()
    }
}
