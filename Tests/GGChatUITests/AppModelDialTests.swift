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
        var open = false
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

    func open() {
        state.withLock { $0.open = true }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        while !state.withLock({ $0.open }) { await Task.yield() }
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
}
