import Foundation
import GGChatCore

extension AppModel {
    /// Whether this provider answers `GET /v1/proxy/status`. Unknown until
    /// probed; false hides the pane.
    public func proxyStatusAvailable(for providerID: UUID) -> Bool {
        proxyStatusAvailability[providerID] ?? false
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
        guard let provider = makeProvider(for: config) as? OpenAICompatibleProvider else {
            proxyStatusAvailability[config.id] = false
            return
        }
        let generation = (probeGeneration[config.id] ?? 0) + 1
        probeGeneration[config.id] = generation
        let snapshot: ProxyStatus?? = try? await provider.proxyStatus()
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
