import GGChatCore
import Synchronization

/// A dial that does not land until it is let through.
///
/// `MockPipeConnector.connect` has no suspension point in it at all, so no
/// other test in this file's neighbourhood can see the window between a dial
/// going out and its session being installed — every one of them awaits a
/// dial that has already finished. This holds that window open on purpose.
///
/// It is no longer the only place the window exists. `ModelpipeConnector`
/// suspends on a real dial, so in a shipped build every dial opens it, and
/// `AppModelQuietDialTests` reaches it from the other side by cancelling one
/// mid-flight. What is still unique here is holding it open *deliberately*,
/// which is what lets the interlock be asserted rather than raced for.
final class GatedConnector: PipeConnector {
    private struct State {
        var arrivals = 0
        var released = 0
        var sessions: [MockPipeSession] = []
    }

    private let inner: MockPipeConnector
    private let state = Mutex(State())

    init(registry: LoopbackProviderRegistry) {
        inner = MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry)
    }

    /// Every session the held dials produced, in the order they landed.
    var sessions: [MockPipeSession] {
        state.withLock { $0.sessions }
    }

    /// How many dials have reached the gate, released or not.
    var arrivals: Int {
        state.withLock { $0.arrivals }
    }

    /// Lets every dial through: the ones waiting and the ones still to come.
    func open() {
        state.withLock { $0.released = .max }
    }

    /// Lets the first `count` dials through in the order they went out, and
    /// goes on holding the rest — which is how a superseded dial can be
    /// watched all the way back while its successor is still in flight.
    func release(_ count: Int) {
        state.withLock { $0.released = max($0.released, count) }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        // Taken before the first suspension, so a dial that has reached
        // `idle` has already taken its place in the queue.
        let mine = state.withLock { state -> Int in
            state.arrivals += 1
            return state.arrivals
        }
        while state.withLock({ $0.released < mine }) { await Task.yield() }
        let session = try await inner.connect(ticket: ticket, token: token)
        if let mock = session as? MockPipeSession { state.withLock { $0.sessions.append(mock) } }
        return session
    }

    /// Nothing here pairs; these tests are about what a dial leaves behind.
    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        throw PipeConnectError.unavailable
    }
}
