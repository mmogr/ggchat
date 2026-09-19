import Foundation
import GGChatCore

/// What a conversation on screen needs from its provider: a pipe that is up,
/// a list of models, and an answer about the status pane. The model does it,
/// in a task of its own, so no view can call it off.
///
/// It used to be the views' own work. The composer dialled and listed the
/// models inside a `.task(id:)`, and the chat view probed the pane inside
/// another, keyed on the connected pulse. On iOS 27.0, with the split view
/// collapsed as it is on a phone, a conversation opened from the list after
/// going back from one, or started from the list's toolbar then, is shown,
/// and each view is told, within a millisecond of appearing, that it has
/// disappeared. SwiftUI calls their tasks off as they start and does not
/// start them again while the chat stays on screen. That was measured on the
/// simulator; the phone in #126 logged two requests ending `-999` at each
/// of four openings before its relaunch, which the code says were these two.
/// A list asked for there failed as "Could not reach the server: cancelled",
/// and a pipe with nothing listed never got a list.
extension AppModel {
    /// Readies a provider for the conversation on screen: dials its pipe if
    /// none is up, then catches it up. Returns at once. The work runs in the
    /// model's own task, which the caller's cancellation does not reach, and
    /// a second call while it runs adds nothing to it.
    ///
    /// From here on the provider is followed. Each time its pipe comes up,
    /// `setPipeStatus` catches it up again, quietly, so a pipe that was not
    /// answering yet when the conversation opened gets its models the moment
    /// it is.
    @discardableResult
    public func open(_ config: ProviderConfig) -> Task<Void, Never> {
        followed.insert(config.id)
        if let running = opening[config.id] { return running }
        let task = Task { [weak self] in
            guard let self else { return }
            if config.isPipe, pipeSessions[config.id] == nil {
                await connectPipe(for: config)
            }
            await catchUp(config.id)
            opening[config.id] = nil
        }
        opening[config.id] = task
        return task
    }

    /// Lists the provider's models if it has none, and asks about its status
    /// pane, for a provider that can answer now.
    ///
    /// A pipe that is not connected is left alone, and its pulse catches it up
    /// instead. `connect` returns once the local port is bound, before the far
    /// machine answers, and this device's own end of the pipe answers `502`
    /// `tunnel_unavailable` in that gap: a refresh sent then got "no tunnel to
    /// the serving side is connected right now", and nothing asked again. A
    /// pipe that did not come up at all has no models to list either, and
    /// asking anyway replaced the connector's own sentence about why with a
    /// generic one.
    ///
    /// Read by id, because the provider may have been edited or removed since
    /// the caller last looked.
    ///
    /// - Parameters:
    ///   - providerID: the provider to catch up.
    ///   - quietly: whether a list that fails should stay out of the alert. A
    ///     pipe coming up is not something the person asked for at that
    ///     moment; the resume that dials it again says nothing either. The
    ///     cost: when a conversation was opened before its pipe was up, the
    ///     list it asked for comes from the pulse, and if that fails the model
    ///     picker stays empty with no alert.
    func catchUp(_ providerID: UUID, quietly: Bool = false) async {
        guard let config = providers.first(where: { $0.id == providerID }) else { return }
        if config.isPipe, pipeSessions[config.id] == nil || pipeStatuses[config.id]?.isConnected != true {
            return
        }
        if models(for: config.id).isEmpty {
            await refreshModels(for: config, quietly: quietly)
        }
        await probeProxyStatus(for: config)
    }
}
