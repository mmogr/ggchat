import Synchronization

#if canImport(Network)
    import Network
#endif

/// Says when the network under this device has changed.
///
/// The seam between the app and `NWPathMonitor`, so that what the app does
/// with a change can be tested without a network to move. It is here rather
/// than in `GGChatUI` because it has to be `Sendable`, which that target's
/// default main-actor isolation fights, as it does `PipeConnector`.
public protocol NetworkPathWatching: Sendable {
    /// Every change from here on, one element each. The network as it already
    /// is when watching starts is not a change.
    func changes() -> AsyncStream<Void>
}

#if canImport(Network)
    /// `NWPathMonitor`, reduced to "the network moved".
    ///
    /// A path is passed on only when it is usable and differs from the last
    /// usable one in its interfaces or its gateways. Walking out of wifi range
    /// onto cellular changes the first; joining a different wifi network on
    /// the same interface changes the second, unless both routers answer at
    /// the same address. A monitor repeating a path it has already described
    /// changes neither, and is not news.
    ///
    /// Each call to ``changes()`` runs a monitor of its own, cancelled when its
    /// stream ends.
    public struct NWPathNetworkWatcher: NetworkPathWatching {
        public init() {}

        public func changes() -> AsyncStream<Void> {
            AsyncStream { continuation in
                let monitor = NWPathMonitor()
                let last = LastPath()
                monitor.pathUpdateHandler = { path in
                    guard path.status == .satisfied else { return }
                    let seen = path.availableInterfaces.map(\.name) + path.gateways.map { "\($0)" }
                    if last.replace(with: Set(seen)) {
                        continuation.yield()
                    }
                }
                continuation.onTermination = { _ in monitor.cancel() }
                monitor.start(queue: DispatchQueue(label: "com.mattogrady.ggchat.network-path"))
            }
        }
    }

    /// The last usable path, as the set of what it went through.
    private final class LastPath: Sendable {
        private let seen = Mutex<Set<String>?>(nil)

        /// Records `now`, and says whether it differs from a path recorded
        /// before. The first is only recorded: it is the network as it already
        /// was, not a change to it.
        func replace(with now: Set<String>) -> Bool {
            seen.withLock { previous in
                defer { previous = now }
                return previous.map { $0 != now } ?? false
            }
        }
    }
#endif
