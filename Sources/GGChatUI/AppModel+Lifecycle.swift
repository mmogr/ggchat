import GGChatCore

// The two ends of a scene phase, split from `AppModel+Pipe` because that file
// is at its size budget and because these are not about pipes: they are about
// the app being taken away and given back, and what a pipe has to do about
// that is one of the consequences rather than the subject.
extension AppModel {
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
            await connectPipe(for: config, quietly: true)
        }
    }

    /// The app is going away: the reply in flight is put down and every pipe
    /// is hung up.
    ///
    /// There is no brief-background regime worth holding a pipe open for.
    /// iOS reclaims a suspended process's sockets without telling it —
    /// TN2277, *Networking and Multitasking*, says to close listening
    /// sockets on the way out for exactly this reason — and nothing tells
    /// this side when the far one gives up either, so a status is only ever
    /// as fresh as the last thing that arrived over a socket the system may
    /// already have taken back. Holding a pipe buys a few seconds and pays
    /// with a pill reading "Direct" over nothing. So the choice is binary,
    /// and this is the half of it that costs a reconnect instead of a lie.
    ///
    /// The reply is cancelled and waited for first, so its partial text
    /// reaches the conversation while there is still a runtime to write it:
    /// a process killed for memory while streaming otherwise leaves the
    /// user's question with no answer under it and no error either.
    ///
    /// Which provider that reply belonged to has to be read before it is put
    /// down. `finish(_:finished:)` clears `liveReply`, so by the time the
    /// pipes are hung up below nothing is left to say that the close about to
    /// be shown is the one that ended a reply — and ADR 0002 counts that
    /// close as mid-reply, because the partial written a line earlier is
    /// exactly what Continue is offered on.
    public func didEnterBackground() async {
        // Held for the whole of it, because all of it is now real work: the
        // reply is awaited down and each pipe is closed over the network. See
        // `BackgroundAssertion` for what is lost when the system suspends the
        // app part-way through.
        let assertion = BackgroundAssertion(name: "hang up the pipes")
        defer { assertion.end() }

        let cutShort = streamingProviderID
        if let inFlight = streamTask {
            inFlight.cancel()
            await inFlight.value
        }
        for config in providers where config.isPipe && pipeStatuses[config.id] != nil {
            await disconnectPipe(for: config.id, leaving: .closed, cutShort: config.id == cutShort)
        }
    }
}
