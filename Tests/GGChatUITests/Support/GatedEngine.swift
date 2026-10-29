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
final class GatedEngine: LocalEngine {
    private struct State {
        var serves = 0
        var servesHeld: Bool
        var shutdowns = 0
        var shutdownsHeld: Bool
    }

    private let inner: MockEngine
    private let state: Mutex<State>

    init(registry: LoopbackProviderRegistry, holdingServes: Bool, holdingShutdowns: Bool) {
        inner = MockEngine(registry: registry)
        state = Mutex(State(servesHeld: holdingServes, shutdownsHeld: holdingShutdowns))
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
        state.withLock { $0.serves += 1 }
        while state.withLock({ $0.servesHeld }) { await Task.yield() }
        return GatedEngineSession(inner: try await inner.serve(reading: reading), engine: self)
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
