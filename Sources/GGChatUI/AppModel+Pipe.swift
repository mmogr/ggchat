import Foundation
import GGChatCore

extension AppModel {
    public func pipeStatus(for providerID: UUID) -> PipeStatus? {
        pipeStatuses[providerID]
    }

    public func pipeSession(for providerID: UUID) -> (any PipeSession)? {
        pipeSessions[providerID]
    }

    /// Whether the reconnect affordance is worth offering for this provider.
    ///
    /// It is offered in every state but one: while a dial is already in
    /// flight, because asking for a second one is not a way back. It is
    /// offered over a pill that reads "Direct" too, because a status is only
    /// ever as fresh as the last thing the far side said, and after a
    /// suspension, a sleep or a network change it can be describing a socket
    /// that is already gone.
    ///
    /// Gating this on the status being `closed` is what left the app showing
    /// a stale *and* disabled pill with no way out of it: nothing writes
    /// `idle` when a pipe dies quietly, so the pill went on claiming a live
    /// connection and refusing to be pressed about it.
    public func canReconnect(_ providerID: UUID) -> Bool {
        !connecting.contains(providerID)
    }

    /// Pairs with a machine and adds it as a provider: redeem the six-digit
    /// code through the pipe for that machine's API key, keep the key as the
    /// provider's token, then dial the pipe the ordinary way.
    ///
    /// The key is stored before the dial, so a redeemed code is never spent
    /// for nothing — a dial that fails afterwards leaves a provider that can
    /// be reconnected, not a machine that has to be enabled again.
    ///
    /// Throws rather than reporting, for the same reason ``addProvider(_:credentials:)``
    /// does: the form that calls this is a sheet, and an alert raised behind
    /// a dismissing sheet is never seen.
    public func addPairedProvider(_ config: ProviderConfig, ticket: String, code: String) async throws {
        let pairing = PipePairing(connector: pipeConnector, redeemer: redeemer)
        let key = try await pairing.token(ticket: ticket, code: code)
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
    public func updatePairedProvider(_ config: ProviderConfig, ticket: String, code: String) async throws {
        let pairing = PipePairing(connector: pipeConnector, redeemer: redeemer)
        let key = try await pairing.token(ticket: ticket, code: code)
        try updateProvider(config, credentials: [.ticket: ticket, .token: key])
        log.log(.info, "paired with \(config.name) again; the new code was redeemed for its key")
        await reconnectPipe(for: config)
    }

    /// Dials the pipe behind a provider, if it is not already up. The status
    /// pill follows the session from here on; a failure is the connector's
    /// own sentence.
    ///
    /// The dial is stamped with a generation and only installs its session if
    /// that stamp is still the current one when it returns — see
    /// ``disconnectPipe(for:)`` for what moves it on.
    public func connectPipe(for config: ProviderConfig) async {
        guard config.isPipe, pipeSessions[config.id] == nil, !connecting.contains(config.id) else { return }
        guard let ticket = try? secrets.secret(.ticket, for: config.id),
            let token = try? secrets.secret(.token, for: config.id)
        else {
            lastError = "The ticket or token for \(config.name) is missing from the Keychain."
            return
        }
        let generation = (dialGeneration[config.id] ?? 0) + 1
        dialGeneration[config.id] = generation
        connecting.insert(config.id)
        // Only if this is still the dial in flight: a superseded one must not
        // clear the flag its successor is relying on.
        defer { if dialGeneration[config.id] == generation { connecting.remove(config.id) } }
        pipeStatuses[config.id] = .idle
        do {
            let session = try await pipeConnector.connect(ticket: ticket, token: token)
            guard dialGeneration[config.id] == generation else {
                // Called off, or dialled again, while this one was in flight.
                // Installing it now would leave a live connection, a bound
                // port and a status task belonging to a provider nothing on
                // screen still points at, so this dial hangs up its own
                // session and says nothing.
                await session.shutdown()
                return
            }
            pipeSessions[config.id] = session
            diagnostics.recordTicket(digest: Ticket.digest(ticket))
            log.log(.info, "pipe up for \(config.name) at \(Redaction.describe(session.baseURL))")
            statusTasks[config.id]?.cancel()
            statusTasks[config.id] = Task { [weak self] in
                for await status in session.status {
                    self?.observe(status, for: config.id)
                }
            }
        } catch {
            guard dialGeneration[config.id] == generation else { return }
            // Closed rather than absent. A provider with no status has no
            // pill at all, and the pill is the only way back: a dial that
            // failed is exactly when one is wanted.
            pipeStatuses[config.id] = .closed
            report(error)
        }
    }

    /// Tears the session down and dials again. The reconnect affordance.
    public func reconnectPipe(for config: ProviderConfig) async {
        await disconnectPipe(for: config.id)
        await connectPipe(for: config)
    }

    /// Hangs up, and calls off any dial still in flight for this provider.
    ///
    /// Calling off the dial is what the generation is for. This can only ever
    /// see a session that has already been installed, so before the stamp a
    /// removal or a teardown that landed mid-dial found nothing to close —
    /// and the dial went on to install a live session for a provider that no
    /// longer existed, with a status task nothing would cancel. The mock's
    /// `connect` never suspends, so that window is invisible from here; a
    /// real connector leaves a QUIC connection and a bound port in it.
    public func disconnectPipe(for providerID: UUID) async {
        dialGeneration[providerID] = (dialGeneration[providerID] ?? 0) + 1
        connecting.remove(providerID)
        statusTasks[providerID]?.cancel()
        statusTasks[providerID] = nil
        // Shut down before forgetting the session, so "no session" also
        // means "its status stream has finished".
        if let session = pipeSessions[providerID] {
            await session.shutdown()
            pipeSessions[providerID] = nil
        }
        pipeStatuses[providerID] = nil
    }

    private func observe(_ status: PipeStatus, for providerID: UUID) {
        let previous = pipeStatuses[providerID]
        pipeStatuses[providerID] = status
        if status == .closed, previous != .closed {
            let streamingHere =
                liveReply.flatMap { live in
                    conversations.first { $0.id == live.conversationID }?.providerID == providerID
                } ?? false
            diagnostics.recordClosed(whileStreaming: streamingHere)
            log.log(.info, "pipe closed\(streamingHere ? " mid-reply" : "")")
        }
        if status.isConnected, previous?.isConnected != true {
            connectedPulse &+= 1
        }
    }

    /// The pipe's provider: an ordinary OpenAI-compatible provider at the
    /// session's loopback URL with the token as its key.
    func makePipeProvider(for config: ProviderConfig) -> (any Provider)? {
        guard let session = pipeSessions[config.id] else {
            lastError = "\(config.name) is not connected yet."
            return nil
        }
        let token = try? secrets.secret(.token, for: config.id)
        return registry.makeProvider(baseURL: session.baseURL, apiKey: token, log: log)
    }

    /// ADR 0001's reading, and the way back in: the app came to the
    /// foreground.
    ///
    /// Every pipe this app has dialled before and is not holding now is
    /// dialled again here. Nothing survives a background — see
    /// ``didEnterBackground()`` — and the composer's `task` does not run a
    /// second time for a conversation that was already on screen, so without
    /// this the app comes back to a pipe that is gone and never notices.
    public func didBecomeActive() async {
        diagnostics.recordResume(at: now())
        for config in providers
        where config.isPipe && pipeSessions[config.id] == nil && pipeStatuses[config.id] != nil {
            await connectPipe(for: config)
        }
    }

    /// The app is going away: the reply in flight is put down and every pipe
    /// is hung up.
    ///
    /// There is no brief-background regime worth holding a pipe open for.
    /// iroh gives a path fifteen seconds of idle before it is gone and
    /// clamps any longer per-path timeout, and iOS reclaims a suspended
    /// process's sockets without telling it — TN2277 says to close listening
    /// sockets on the way out for exactly this reason. Holding one buys a
    /// few seconds and pays with a pill reading "Direct" over a socket the
    /// system already took back. So the choice is binary, and this is the
    /// half of it that costs a reconnect instead of a lie.
    ///
    /// The reply is cancelled and waited for first, so its partial text
    /// reaches the conversation while there is still a runtime to write it:
    /// a process killed for memory while streaming otherwise leaves the
    /// user's question with no answer under it and no error either.
    public func didEnterBackground() async {
        if let inFlight = streamTask {
            inFlight.cancel()
            await inFlight.value
        }
        for config in providers where config.isPipe && pipeStatuses[config.id] != nil {
            await disconnectPipe(for: config.id)
            // Closed rather than absent, for ``connectPipe(for:)``'s reason:
            // a provider with no status has no pill, and this is precisely
            // the state a way back has to be offered from.
            pipeStatuses[config.id] = .closed
        }
    }
}
