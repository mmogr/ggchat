import Foundation
import GGChatCore

/// Pairing: trading a one-time code for this device's key, over a pipe the
/// provider then keeps.
///
/// Split from `AppModel+Pipe` because these two are not pipe plumbing. They
/// spend a credential, they are the only pipe paths that `throw` rather than
/// report, and they are what a sheet calls — the same argument that put the
/// resume and the hang-up in `AppModel+Lifecycle`.
extension AppModel {
    /// Pairs with a machine and adds it as a provider: modelpipe dials the
    /// ticket in the pairing string, waits for the far machine, spends the
    /// code there for a key minted for this device, and hands back that key
    /// and the pipe it was redeemed over. The key becomes the provider's
    /// token and the pipe becomes its first session.
    ///
    /// No second dial. The pipe is up and reached by the time the key exists,
    /// so hanging it up to dial again would cost another hole punch and
    /// another endpoint identity — and the fingerprint the far machine
    /// recorded as it minted the key would never be the one this device then
    /// chats from.
    ///
    /// The key is stored before the session is installed, so a redeemed code
    /// is never spent for nothing: whatever happens to the pipe afterwards
    /// leaves a provider that can be reconnected, not a machine that has to
    /// invite this device again.
    ///
    /// `deviceName` is what the far machine will list this device as, if it
    /// keeps a list. It has no default on purpose: `config.name` names the
    /// far machine, and a form that forgot to pass the other name should fail
    /// to build, not send none.
    ///
    /// Throws rather than reporting, for the same reason ``addProvider(_:credentials:)``
    /// does: the form that calls this is a sheet, and an alert raised behind
    /// a dismissing sheet is never seen.
    ///
    /// - Parameters:
    ///   - config: the provider to add once the code has been spent.
    ///   - pairing: the whole `ticket-code` string, as pasted or scanned.
    ///   - ticket: the ticket inside it, which is what the Keychain keeps and
    ///     what a later dial uses. `MpPaired` carries no ticket back, so it
    ///     is split off on this side.
    ///   - deviceName: what the far machine should list this device as, or
    ///     `nil` to send none.
    public func addPairedProvider(
        _ config: ProviderConfig, pairing: String, ticket: String, deviceName: String?
    ) async throws {
        let paired = try await pair(pairing, deviceName: deviceName, holding: config.id)
        try addProvider(config, credentials: [.ticket: ticket, .token: paired.token])
        log.log(.info, "paired with \(config.name) as \(paired.device); the pipe it paired over is its own")
        await keep(paired, for: config, ticket: ticket)
    }

    /// Pairs again with a machine already on the list: spend the new code
    /// through the pasted ticket, put the key and the ticket in place of the
    /// old pair, hang the old pipe up and keep the new one. The provider's id
    /// survives, and with it its conversations — see
    /// ``updateProvider(_:credentials:)``.
    ///
    /// A refused code never reaches the old session. The pairing runs first
    /// and throws where it fails, so a machine that has stopped admitting
    /// this device leaves the provider exactly as it was, still connected to
    /// whatever it was connected to.
    ///
    /// The old pipe goes only once the new key is stored, because a new
    /// ticket does nothing without a new pipe: a ticket is read at dial time
    /// alone, so an edited one sitting behind a live session would be a
    /// setting that had visibly been saved and changed nothing.
    ///
    /// The device name is asked for again rather than remembered: it goes out
    /// with the pairing and is kept nowhere on this side.
    public func updatePairedProvider(
        _ config: ProviderConfig, pairing: String, ticket: String, deviceName: String?
    ) async throws {
        let paired = try await pair(pairing, deviceName: deviceName, holding: config.id)
        try updateProvider(config, credentials: [.ticket: ticket, .token: paired.token])
        log.log(.info, "paired with \(config.name) again, as \(paired.device); the new pipe is its own")
        await disconnectPipe(for: config.id)
        await keep(paired, for: config, ticket: ticket)
    }

    /// Pairs, with the provider marked as connecting for as long as it takes.
    ///
    /// ``canReconnect(_:)`` is `!connecting.contains(id)`, so this is what
    /// takes the Reconnect button away while a pairing is out — a press
    /// during ``updatePairedProvider(_:pairing:ticket:deviceName:)`` would
    /// dial the machine being replaced, with the token being replaced, for
    /// the whole of the longest await in the app. It is the affordance that
    /// is closed and not a path: a `reconnectPipe` called from code clears
    /// the flag on its way through `disconnectPipe` and dials anyway.
    ///
    /// The flag is dropped as this returns, before anything is stored or
    /// installed, because `keep` may fall back to `connectPipe`, which
    /// refuses to dial a provider that is already connecting.
    ///
    /// In ``addPairedProvider(_:pairing:ticket:deviceName:)`` it guards
    /// nothing today — the provider is not on the list until the code has
    /// been spent — and it is used there anyway so the two paths cannot
    /// drift apart.
    private func pair(
        _ pairing: String, deviceName: String?, holding providerID: UUID
    ) async throws -> PairedPipe {
        connecting.insert(providerID)
        defer { connecting.remove(providerID) }
        return try await pipeConnector.pair(pairing: pairing, deviceName: deviceName)
    }

    /// Installs the pipe a pairing came up on as the provider's session.
    ///
    /// A pairing that succeeded without a usable pipe still stored its key,
    /// so the provider is dialled the ordinary way instead: the code is spent
    /// either way, and leaving the provider unconnected with no attempt made
    /// would be the one outcome nobody could act on.
    ///
    /// The status is written before the install for the reason
    /// ``connectPipe(for:quietly:)`` writes one before it dials: `installPipe`
    /// can decline to install — the app went to the background while the
    /// pairing was out, which is minutes of chance, not microseconds — and it
    /// says nothing when it does. A provider left with no status has no pill,
    /// and `resumeEveryPipe` skips it for ever, because it dials only what it
    /// already has a status for. `.idle` is what a bailed dial leaves, so it
    /// is what a bailed pairing leaves.
    ///
    /// Of `installPipe`'s two guards only `!isAway` can fire here: the stamp
    /// is taken after the pairing returned and nothing can have moved it on
    /// in between, all of this being one MainActor hop.
    private func keep(_ paired: PairedPipe, for config: ProviderConfig, ticket: String) async {
        guard let session = paired.session else {
            await connectPipe(for: config)
            return
        }
        setPipeStatus(.idle, for: config.id)
        await installPipe(session, for: config, ticket: ticket, generation: nextDialGeneration(for: config.id))
    }
}
