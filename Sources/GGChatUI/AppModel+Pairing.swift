import GGChatCore

/// Pairing: redeeming a one-time code through a pipe for a machine's key.
///
/// Split from `AppModel+Pipe` because these two are not pipe plumbing. They
/// spend a credential, they are the only pipe paths that `throw` rather than
/// report, and they are what a sheet calls — the same argument that put the
/// resume and the hang-up in `AppModel+Lifecycle`.
extension AppModel {
    /// Pairs with a machine and adds it as a provider: redeem the six-digit
    /// code through the pipe for that machine's API key, keep the key as the
    /// provider's token, then dial the pipe the ordinary way.
    ///
    /// The key is stored before the dial, so a redeemed code is never spent
    /// for nothing — a dial that fails afterwards leaves a provider that can
    /// be reconnected, not a machine that has to be enabled again.
    ///
    /// `deviceName` is what the far machine will list this device as, if it
    /// keeps a list. It has no default on purpose: `config.name` names the
    /// far machine, and a form that forgot to pass the other name should fail
    /// to build, not send none.
    ///
    /// Throws rather than reporting, for the same reason ``addProvider(_:credentials:)``
    /// does: the form that calls this is a sheet, and an alert raised behind
    /// a dismissing sheet is never seen.
    public func addPairedProvider(
        _ config: ProviderConfig, ticket: String, code: String, deviceName: String?
    ) async throws {
        let pairing = PipePairing(connector: pipeConnector, redeemer: redeemer)
        let key = try await pairing.token(ticket: ticket, code: code, deviceName: deviceName)
        try addProvider(config, credentials: [.ticket: ticket, .token: key])
        log.log(.info, "paired with \(config.name); the code was redeemed for its key")
        await connectPipe(for: config)
    }

    /// Pairs again with a machine already on the list: redeem the code
    /// through the new ticket, put both in place of the old pair, and dial
    /// again. The provider's id survives, and with it its conversations —
    /// see ``updateProvider(_:credentials:)``.
    ///
    /// The dial is part of the edit because a new ticket does nothing
    /// without one. A replaced token takes effect on the next request, since
    /// `makePipeProvider(for:)` reads it each time; a ticket is only ever
    /// read at dial time, so an edited ticket sitting behind a live session
    /// would be a setting that had visibly been saved and changed nothing.
    ///
    /// The device name is asked for again rather than remembered: it goes
    /// out with the redeem and is kept nowhere on this side.
    public func updatePairedProvider(
        _ config: ProviderConfig, ticket: String, code: String, deviceName: String?
    ) async throws {
        let pairing = PipePairing(connector: pipeConnector, redeemer: redeemer)
        let key = try await pairing.token(ticket: ticket, code: code, deviceName: deviceName)
        try updateProvider(config, credentials: [.ticket: ticket, .token: key])
        log.log(.info, "paired with \(config.name) again; the new code was redeemed for its key")
        await reconnectPipe(for: config)
    }
}
