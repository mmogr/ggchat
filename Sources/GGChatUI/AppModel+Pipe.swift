import Foundation
import GGChatCore

extension AppModel {
    public func pipeStatus(for providerID: UUID) -> PipeStatus? {
        pipeStatuses[providerID]
    }

    public func pipeSession(for providerID: UUID) -> (any PipeSession)? {
        pipeSessions[providerID]
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
            pipeStatuses[config.id] = nil
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

    /// ADR 0001's reading: the app came back to the foreground.
    public func didBecomeActive() {
        diagnostics.recordResume(at: now())
    }
}
