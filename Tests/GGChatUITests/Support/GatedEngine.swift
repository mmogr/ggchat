import Foundation
import GGChatCore
import Synchronization

/// An engine whose serves, and whose sessions' shutdowns, wait until a test
/// lets them through.
///
/// `MockEngine.serve` and `MockEngineSession.shutdown` have no suspension
/// point that waits on anything, so nothing built on the mock alone holds
/// open the windows gglib's engine has: a serve still starting, and a
/// session still going down while its port is bound. This holds each open
/// on purpose, as `GatedConnector` holds a dial and `HeldShutdownConnector` a
/// hang-up, and counts what has reached each gate so a test can wait for a
/// window to open before acting inside it.
///
/// Each serve is the mock's with the next of `behaviours`, the last kept for
/// every serve after, so a test can have a load fail and the next serve's
/// succeed, as a fresh one may. `behaviours` names one at least.
final class GatedEngine: LocalEngine {
    private struct State {
        var serves = 0
        var servesHeld: Bool
        var shutdowns = 0
        var shutdownsHeld: Bool
    }

    private let inner: [MockEngine]
    private let state: Mutex<State>

    init(
        registry: LoopbackProviderRegistry, holdingServes: Bool, holdingShutdowns: Bool,
        behaviours: [MockEngine.Behaviour] = [.ready], sleeper: any Sleeper = ImmediateSleeper(),
        provider: (any Provider)? = nil
    ) {
        precondition(!behaviours.isEmpty, "a GatedEngine serves with one behaviour at least")
        inner = behaviours.map { behaviour in
            MockEngine(behaviour: behaviour, sleeper: sleeper, registry: registry, provider: provider)
        }
        state = Mutex(State(servesHeld: holdingServes, shutdownsHeld: holdingShutdowns))
    }

    /// How many serves have reached the gate, let through or not.
    var serves: Int {
        state.withLock { $0.serves }
    }

    /// How many sessions have begun going down, let through or not.
    var shutdowns: Int {
        state.withLock { $0.shutdowns }
    }

    var isAvailable: Bool { true }

    /// Waits, for up to `limit`, until `count` serves have reached the gate,
    /// and answers whether they did. Polled on a clock rather than counted
    /// in yields, for `GatedConnector.waitForArrivals`'s reason.
    func waitForServes(_ count: Int, within limit: Duration = .seconds(10)) async -> Bool {
        await wait(within: limit) { $0.serves >= count }
    }

    /// Waits, for up to `limit`, until `count` sessions have begun going
    /// down, and answers whether they did.
    func waitForShutdowns(_ count: Int, within limit: Duration = .seconds(10)) async -> Bool {
        await wait(within: limit) { $0.shutdowns >= count }
    }

    /// Lets every serve through: the ones waiting and the ones still to come.
    func releaseServes() {
        state.withLock { $0.servesHeld = false }
    }

    /// Lets every shutdown through: the ones waiting and the ones still to
    /// come.
    func releaseShutdowns() {
        state.withLock { $0.shutdownsHeld = false }
    }

    func serve(reading: DeviceReading) async throws -> any EngineSession {
        let index = state.withLock { state in
            state.serves += 1
            return state.serves - 1
        }
        while state.withLock({ $0.servesHeld }) { await Task.yield() }
        let engine = inner[min(index, inner.count - 1)]
        return GatedEngineSession(inner: try await engine.serve(reading: reading), engine: self)
    }

    fileprivate func shutdownStarted() {
        state.withLock { $0.shutdowns += 1 }
    }

    fileprivate var isHoldingShutdowns: Bool {
        state.withLock { $0.shutdownsHeld }
    }

    private func wait(within limit: Duration, until done: (State) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !state.withLock({ done($0) }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return state.withLock { done($0) }
    }
}

/// The session behind ``GatedEngine``: everything forwards to the mock's
/// except `shutdown()`, which waits to be let through.
final class GatedEngineSession: EngineSession, Sendable {
    private let inner: any EngineSession
    private let engine: GatedEngine

    fileprivate init(inner: any EngineSession, engine: GatedEngine) {
        self.inner = inner
        self.engine = engine
    }

    var baseURL: URL { inner.baseURL }
    var apiKey: String { inner.apiKey }
    var status: AsyncStream<EngineStatus> { inner.status }

    func shutdown() async {
        engine.shutdownStarted()
        while engine.isHoldingShutdowns { await Task.yield() }
        await inner.shutdown()
    }
}
