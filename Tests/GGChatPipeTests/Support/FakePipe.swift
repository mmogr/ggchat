import Modelpipe
import Synchronization

/// A pipe with no network, no port and no far machine, so everything the
/// connector and the session do can be driven a step at a time.
///
/// A `final class` because `MpPipeProtocol` refines `AnyObject`. uniffi offers
/// `MpPipe.NoHandle` for the same purpose, but conforming to the protocol is
/// the point here: the session is written against `any MpPipeProtocol`
/// precisely so that the real object never has to exist in a test.
final class FakePipe: MpPipeProtocol, @unchecked Sendable {
    private struct State {
        var pending: [MpPipeStatus]
        var current: MpPipeStatus
        var shutdowns = 0
        var networkChanges = 0
        var reason: MpCloseReason?
    }

    private let state: Mutex<State>
    private let url: String
    /// Suspends `statusChangedSince` once the walk is spent, instead of
    /// ending the sequence. A real pipe that reaches `relayed` and stays there
    /// does not close, and a fake that closed instead would make every test
    /// about a settled status secretly a test about a closing one.
    private let held = AsyncStream<Never>.makeStream()
    private let stayOpen: Bool

    /// - Parameters:
    ///   - walk: the transitions `statusChangedSince` will hand out, in order.
    ///     When they run out the sequence ends, which is what a close looks
    ///     like to the caller.
    ///   - baseUrl: what the pipe claims to have bound.
    init(
        walk: [MpPipeStatus] = [],
        from initial: MpPipeStatus = .idle,
        baseUrl: String = "http://127.0.0.1:51234/v1",
        reason: MpCloseReason? = nil,
        stayOpen: Bool = false
    ) {
        self.state = Mutex(State(pending: walk, current: initial, reason: reason))
        self.url = baseUrl
        self.stayOpen = stayOpen
    }

    var shutdownCount: Int { state.withLock { $0.shutdowns } }
    var networkChangeCount: Int { state.withLock { $0.networkChanges } }

    func baseUrl() -> String { url }
    func closeReason() -> MpCloseReason? { state.withLock { $0.reason } }
    func port() -> UInt16 { 51234 }

    func networkMetrics() -> MpNetworkMetrics {
        MpNetworkMetrics(
            relayConnections: 3, relayConnectionsFailed: 1, relayConnectionsRatelimited: 0)
    }

    func notifyNetworkChange() async {
        state.withLock { $0.networkChanges += 1 }
    }

    func shutdown() async {
        state.withLock {
            $0.shutdowns += 1
            $0.reason = $0.reason ?? .shutdown
        }
    }

    func status() -> MpPipeStatus { state.withLock { $0.current } }

    /// Hands out the next transition, or `nil` once there are none left.
    ///
    /// Returns without suspending on purpose. What needs to be controlled in
    /// these tests is the grace, and that is the injected `Sleeper`'s job; a
    /// gate here as well would only make the tests harder to read.
    func statusChangedSince(snapshot: MpPipeStatus) async -> MpPipeStatus? {
        let next: MpPipeStatus? = state.withLock { state in
            guard !state.pending.isEmpty else { return nil }
            let value = state.pending.removeFirst()
            state.current = value
            return value
        }
        if let next { return next }
        if stayOpen {
            // Suspends until the task is cancelled, which is what a pipe that
            // is simply still up looks like. `for await` on a stream that
            // never yields exits on cancellation and spins on nothing.
            for await _ in held.stream {}
        }
        return nil
    }
}
