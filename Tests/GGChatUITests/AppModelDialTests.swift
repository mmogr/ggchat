import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A dial that does not land until it is let through.
///
/// `MockPipeConnector.connect` has no suspension point in it at all, so the
/// window between a dial going out and its session being installed does not
/// exist in any other test — every one of them awaits a dial that has
/// already finished. This holds that window open on purpose.
private final class GatedConnector: PipeConnector {
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
}

/// One model holding one pipe provider, whose every dial goes through `gate`.
private struct Fixture {
    let model: AppModel
    let config: ProviderConfig
    let gate: GatedConnector
    let registry: LoopbackProviderRegistry

    /// Runs a dial up to the gate and leaves it standing there.
    @MainActor
    func dial() async -> Task<Void, Never> {
        let task = Task { await model.connectPipe(for: config) }
        for _ in 0..<200 where model.pipeStatus(for: config.id) != .idle { await Task.yield() }
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle, "the dial never went out")
        return task
    }

    /// Which of the sessions the gate produced still hold a bound port.
    @MainActor
    var stillBound: [URL] {
        gate.sessions.map(\.baseURL).filter { registry.provider(for: $0) != nil }
    }
}

final class AppModelDialTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeFixture() throws -> Fixture {
        let registry = LoopbackProviderRegistry()
        let connector = GatedConnector(registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelDialTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return Fixture(model: model, config: config, gate: connector, registry: registry)
    }

    /// The window the interlock is about: a dial that returns after its
    /// provider was hung up must hang itself up, not install a live
    /// connection that nothing above still has a way to close.
    @MainActor
    func testADialThatLandsAfterADisconnectHangsUpInsteadOfInstallingItself() async throws {
        let fixture = try makeFixture()
        let inFlight = await fixture.dial()

        await fixture.model.disconnectPipe(for: fixture.config.id)
        fixture.gate.open()
        await inFlight.value

        let id = fixture.config.id
        XCTAssertNil(fixture.model.pipeSession(for: id), "the late dial installed its session anyway")
        XCTAssertNil(fixture.model.pipeStatus(for: id), "and put a status back on a provider that was hung up")
        XCTAssertNil(fixture.model.statusTasks[id], "and left a status task nothing would cancel")
        XCTAssertEqual(
            fixture.stillBound, [],
            "the orphaned session was dropped rather than shut down, so its port is still bound")
    }

    /// The same window, through the caller that actually meets it: deleting
    /// a provider while its first dial is still out.
    @MainActor
    func testRemovingAProviderMidDialLeavesNoConnectionBehind() async throws {
        let fixture = try makeFixture()
        let inFlight = await fixture.dial()

        fixture.model.removeProvider(fixture.config.id)
        // `removeProvider` hangs the pipe up on a task of its own; that task
        // has run once the status it clears is gone.
        for _ in 0..<200 where fixture.model.pipeStatus(for: fixture.config.id) != nil { await Task.yield() }
        fixture.gate.open()
        await inFlight.value

        XCTAssertTrue(fixture.model.providers.isEmpty)
        XCTAssertNil(
            fixture.model.pipeSession(for: fixture.config.id), "a deleted provider ended up holding a live pipe")
        XCTAssertEqual(fixture.stillBound, [], "the deleted provider's port was left bound")
    }

    /// Two dials in flight at once leave one connection, not two: whichever
    /// is superseded hangs itself up rather than being dropped on the floor.
    @MainActor
    func testTwoOverlappingDialsLeaveExactlyOneConnection() async throws {
        let fixture = try makeFixture()
        let first = await fixture.dial()
        await fixture.model.disconnectPipe(for: fixture.config.id)
        let second = await fixture.dial()

        fixture.gate.open()
        await first.value
        await second.value

        XCTAssertEqual(fixture.gate.sessions.count, 2, "both dials should have gone out")
        let installed = try XCTUnwrap(
            fixture.model.pipeSession(for: fixture.config.id), "neither dial installed anything")
        XCTAssertEqual(
            fixture.stillBound, [installed.baseURL],
            "the superseded dial's session was left bound alongside the installed one")
    }

    /// A `ProviderConfig` is a value, and callers carry one across
    /// suspensions — the resume walks a whole list of them. One deleted in
    /// between has no pipe to dial, and complaining that its credentials are
    /// missing is worse than silence: they are missing because it was
    /// deleted, and the user is looking at a list it is no longer on.
    @MainActor
    func testAProviderThatIsNoLongerOnTheListIsNotDialled() async throws {
        let fixture = try makeFixture()
        fixture.gate.open()
        fixture.model.removeProvider(fixture.config.id)

        await fixture.model.connectPipe(for: fixture.config)

        XCTAssertNil(fixture.model.pipeSession(for: fixture.config.id))
        XCTAssertTrue(fixture.gate.sessions.isEmpty, "a deleted provider was dialled anyway")
        XCTAssertNil(fixture.model.lastError, "a deleted provider was reported as missing its credentials")
    }

    /// What the status pill is gated on. A dial in flight is the one state
    /// where a second dial is not a way back; a "Direct" that has gone stale
    /// is exactly when one is.
    ///
    /// A superseded dial coming back is not the end of a dial in flight: the
    /// in-flight flag it would clear is the one its successor is relying on,
    /// and clearing it offers the pill in the single state that has to
    /// withhold it — and lets a third dial start while the second is still
    /// out.
    @MainActor
    func testOnlyADialInFlightWithholdsTheWayBack() async throws {
        let fixture = try makeFixture()
        let superseded = await fixture.dial()
        XCTAssertFalse(
            fixture.model.canReconnect(fixture.config.id),
            "a dial is already out; asking for a second one is not a way back")

        await fixture.model.disconnectPipe(for: fixture.config.id)
        let inFlight = await fixture.dial()
        fixture.gate.release(1)
        await superseded.value
        XCTAssertFalse(
            fixture.model.canReconnect(fixture.config.id),
            "the superseded dial cleared the in-flight flag its successor was relying on")

        fixture.gate.open()
        await inFlight.value
        for _ in 0..<200 where fixture.model.pipeStatus(for: fixture.config.id) != .direct { await Task.yield() }

        XCTAssertEqual(fixture.model.pipeStatus(for: fixture.config.id), .direct)
        XCTAssertTrue(
            fixture.model.canReconnect(fixture.config.id),
            "a connected status is only as fresh as the last thing the far side said, "
                + "so the pill has to stay a way back")
    }
}
