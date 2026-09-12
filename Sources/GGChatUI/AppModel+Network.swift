import GGChatCore

// Its own file because `AppModel+Pipe` is at its size budget, and along a
// seam: that file dials and hangs up, and this is the one piece of news a pipe
// is given from outside.
extension AppModel {
    /// Starts passing changes to the network under this device on to every
    /// pipe the app holds. Once: a second call finds the task already there.
    ///
    /// From `load()` rather than `didBecomeActive()`. `RootView` hears scene
    /// phases through `onChange`, which does not fire for the phase the app
    /// launches in, so a watcher started there would miss the whole first
    /// stretch in the foreground. Nothing stops it on the way to the
    /// background: every pipe is hung up there, so a change arriving then
    /// finds nothing to tell.
    func startWatchingTheNetwork() {
        guard networkTask == nil else { return }
        let changes = networkWatcher.changes()
        networkTask = Task { [weak self] in
            for await _ in changes {
                await self?.networkDidChange()
            }
        }
    }

    /// The network under this device moved, so every pipe the app holds is
    /// told, and its endpoint looks at the network again now. iroh watches the
    /// routing socket for the same thing, but looks again only when a route
    /// message arrives, so a pipe whose move it missed would stay on dead
    /// paths until they timed out. A notice the endpoint did not need is
    /// harmless.
    ///
    /// Only the sessions this model holds: a dial still in flight has nothing
    /// to be told yet, and lands on whatever network is there when it does.
    func networkDidChange() async {
        for session in pipeSessions.values {
            await session.notifyNetworkChange()
        }
    }
}
