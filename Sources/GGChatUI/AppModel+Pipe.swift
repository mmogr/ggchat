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
    /// ``disconnectPipe(for:leaving:cutShort:)`` for what moves it on.
    ///
    /// A provider that is no longer on the list has no pipe to dial. Callers
    /// hold a `ProviderConfig` by value across suspensions — the resume in
    /// ``didBecomeActive()`` walks a whole list of them — so one deleted in
    /// between would otherwise be dialled, and then reported as missing its
    /// credentials, which it is: they were deleted with it.
    /// - Parameters:
    ///   - config: the provider whose pipe to dial.
    ///   - quietly: whether a failure should raise an alert.
    ///     ``didBecomeActive()`` dials every pipe it is holding none of, and
    ///     a machine that is asleep would otherwise put an alert in front of
    ///     the person on every single return to the foreground — one they did
    ///     not ask for and cannot act on, carrying only the last provider's
    ///     sentence because each failure overwrites the one before it. The
    ///     pill already says "Reconnect"; that is the report for a dial nobody
    ///     asked for. A dial they *did* ask for still says why it failed.
    public func connectPipe(for config: ProviderConfig, quietly: Bool = false) async {
        guard providers.contains(where: { $0.id == config.id }) else { return }
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
        setPipeStatus(.idle, for: config.id)
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
                    self?.setPipeStatus(status, for: config.id)
                }
                // The stream ends only after a close, so the session behind it
                // is finished. Forgetting it is what lets the next dial
                // happen: `connectPipe` refuses while one is installed, and
                // both the composer's task and `didBecomeActive` ask for a
                // dial only when there is none — so a pipe that died quietly
                // used to leave a dead session in the dictionary that nothing
                // but a manual press would clear.
                //
                // Only if this is still the current dial. A teardown has
                // already moved the generation on and installed nothing, and a
                // later dial may have installed a live session that this one
                // must not remove.
                self?.forgetSessionIfCurrent(config.id, generation: generation)
            }
        } catch is CancellationError {
            // The view asked for this dial and went away again — the composer
            // dials inside a `.task(id:)` that SwiftUI cancels on every
            // provider switch. Nobody is waiting for an answer, so there is
            // nobody to tell. Left closed so the pill is still a way back.
            guard dialGeneration[config.id] == generation else { return }
            setPipeStatus(.closed, for: config.id)
        } catch {
            guard dialGeneration[config.id] == generation else { return }
            // Closed rather than absent. A provider with no status has no
            // pill at all, and the pill is the only way back: a dial that
            // failed is exactly when one is wanted.
            setPipeStatus(.closed, for: config.id)
            if quietly {
                log.log(.info, "\(config.name) did not answer: \(error.localizedDescription)")
            } else {
                report(error)
            }
        }
    }

    /// Drops a finished session, unless a newer dial has already replaced it.
    private func forgetSessionIfCurrent(_ providerID: UUID, generation: Int) {
        guard dialGeneration[providerID] == generation else { return }
        pipeSessions[providerID] = nil
    }

    /// Tears the session down and dials again. The reconnect affordance.
    public func reconnectPipe(for config: ProviderConfig) async {
        await disconnectPipe(for: config.id)
        await connectPipe(for: config)
    }

    /// Hangs up, and calls off any dial still in flight for this provider.
    ///
    /// - Parameters:
    ///   - providerID: whose pipe to hang up.
    ///   - status: what the pill is left reading. `nil` — no pill at all — is
    ///     right for a provider being deleted or dialled again. Going to the
    ///     background leaves `.closed`, for ``connectPipe(for:quietly:)``'s reason:
    ///     the pill is the way back, and that is the state it is most wanted
    ///     from. Leaving it here rather than writing it afterwards is what
    ///     puts the close through `setPipeStatus(_:for:cutShort:)` and so
    ///     what counts it. That is the whole of the reason: writing it
    ///     afterwards, as the caller used to, showed the user nothing wrong.
    ///     The clear to `nil` came after the `await` below, and this module
    ///     is compiled with `.defaultIsolation(MainActor.self)`, so nothing
    ///     could run between that write and the caller's.
    ///   - cutShort: whether this hang-up is what ended a reply in flight.
    ///     Only ``didEnterBackground()`` can say so, because it puts the
    ///     reply down before it hangs up — see there.
    ///
    /// Calling off the dial is what the generation is for. This can only ever
    /// see a session that has already been installed, so before the stamp a
    /// removal or a teardown that landed mid-dial found nothing to close —
    /// and the dial went on to install a live session for a provider that no
    /// longer existed, with a status task nothing would cancel. The mock's
    /// `connect` never suspends, so that window is invisible from here; a
    /// real connector leaves a QUIC connection and a bound port in it.
    public func disconnectPipe(for providerID: UUID, leaving status: PipeStatus? = nil, cutShort: Bool = false) async {
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
        setPipeStatus(status, for: providerID, cutShort: cutShort)
    }

    /// The one place `pipeStatuses` is written, and so the one place a close
    /// is counted. Being shown as closed and being counted as a close are the
    /// same event; they used to be two.
    ///
    /// ADR 0002's denominator was kept where a status was *observed*, which
    /// is only what a live session sends. The two closes that come from this
    /// side set the pill and told the counter nothing: a dial that was
    /// refused, and the hang-up on the way to the background. The second is
    /// the phone's commonest close by a distance, so the reading was shown
    /// over a denominator that omitted the case it exists to measure.
    ///
    /// `previous != .closed` is what stops one close being counted twice: a
    /// refused dial leaves `.closed` behind, and the background that follows
    /// it hangs up a provider with nothing left to hang up.
    private func setPipeStatus(_ status: PipeStatus?, for providerID: UUID, cutShort: Bool = false) {
        let previous = pipeStatuses[providerID]
        pipeStatuses[providerID] = status
        if status == .closed, previous != .closed {
            let midReply = cutShort || streamingProviderID == providerID
            diagnostics.recordClosed(whileStreaming: midReply)
            log.log(.info, "pipe closed\(midReply ? " mid-reply" : "")")
        }
        if status?.isConnected == true, previous?.isConnected != true {
            connectedPulse &+= 1
        }
    }

    /// The provider the reply in flight is going through, if there is one.
    ///
    /// Not `private`: `didEnterBackground` reads it, and it lives in
    /// `AppModel+Lifecycle` — a different file, which is what `private` means
    /// in Swift even for two extensions of the same type.
    var streamingProviderID: UUID? {
        liveReply.flatMap { live in
            conversations.first { $0.id == live.conversationID }?.providerID
        }
    }

    /// The pipe's provider: an ordinary OpenAI-compatible provider at the
    /// session's loopback URL with the token as its key.
    func makePipeProvider(for config: ProviderConfig) -> (any Provider)? {
        guard let session = pipeSessions[config.id] else {
            // Never over the top of a sentence already waiting to be read.
            // The dial sets one and the model refresh follows it a moment
            // later, so the connector's own reason for refusing — which is
            // the whole point of `PipeConnectError`'s cases being sentences —
            // used to be replaced by this one before anything showed it.
            if lastError == nil {
                lastError = "\(config.name) is not connected yet."
            }
            return nil
        }
        let token = try? secrets.secret(.token, for: config.id)
        return registry.makeProvider(baseURL: session.baseURL, apiKey: token, log: log)
    }
}
