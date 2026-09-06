import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A connector that refuses every dial, and can be made to refuse it late.
///
/// `MockPipeConnector` only ever fails on a ticket or a token it can see is
/// wrong, and `AppModel` rejects both of those before it dials at all — so
/// without this, nothing in the tests has ever watched a dial go out and come
/// back empty, which is what a machine that is asleep or off the network
/// gives you.
private final class RefusingConnector: PipeConnector {
    private struct State {
        var open: Bool
        var dials = 0
    }

    private let state: Mutex<State>

    /// `held: true` leaves every dial standing at the gate until ``open()``,
    /// so the window between a dial going out and its refusal landing can be
    /// held open on purpose.
    init(held: Bool = false) {
        state = Mutex(State(open: !held))
    }

    /// How many dials have gone out, whether or not they have come back yet.
    var dials: Int {
        state.withLock { $0.dials }
    }

    func open() {
        state.withLock { $0.open = true }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        state.withLock { $0.dials += 1 }
        while !state.withLock({ $0.open }) { await Task.yield() }
        throw PipeConnectError.unavailable
    }
}

/// What a dial that fails leaves behind.
final class AppModelFailedDialTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(dialling connector: any PipeConnector) throws -> (AppModel, ProviderConfig) {
        let defaults = UserDefaults(suiteName: "AppModelFailedDialTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            registry: LoopbackProviderRegistry(), pipeConnector: connector,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    /// A refused dial leaves `closed` rather than no status at all, because
    /// no status is no way back by two separate roads: `Composer` draws the
    /// status pill only `if let status`, so there is nothing on screen to
    /// press; and `didBecomeActive()` dials again only the providers it has
    /// a status for, so the resume will not retry it either. One dial that
    /// failed while the machine was asleep would otherwise be a dead end
    /// until the app was relaunched.
    @MainActor
    func testAFailedDialLeavesAPillToPressAndAResumeThatDialsAgain() async throws {
        let connector = RefusingConnector()
        let (model, config) = try makeModel(dialling: connector)

        await model.connectPipe(for: config)

        XCTAssertNotNil(model.pipeStatus(for: config.id), "a failed dial left no pill at all")
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)
        XCTAssertTrue(model.canReconnect(config.id), "the one state a way back is most wanted from withheld it")
        XCTAssertNotNil(model.lastError, "the refusal was swallowed")
        XCTAssertNil(model.pipeSession(for: config.id))

        await model.didBecomeActive()

        XCTAssertEqual(connector.dials, 2, "the resume did not retry the failed dial")
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed, "and the pill did not survive the resume either")
    }

    /// The failing half of the interlock. A refusal that arrives after its
    /// dial was called off says nothing: the status belongs to whatever
    /// happened next, and an error about a dial nobody is waiting on is an
    /// answer with no question under it.
    @MainActor
    func testARefusalThatArrivesAfterItsDialWasCalledOffSaysNothing() async throws {
        let connector = RefusingConnector(held: true)
        let (model, config) = try makeModel(dialling: connector)
        let inFlight = Task { await model.connectPipe(for: config) }
        for _ in 0..<200 where model.pipeStatus(for: config.id) != .idle { await Task.yield() }
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle, "the dial never went out")

        await model.disconnectPipe(for: config.id)
        connector.open()
        await inFlight.value

        XCTAssertNil(
            model.pipeStatus(for: config.id), "a called-off dial put a status back on a provider that was hung up")
        XCTAssertNil(model.lastError, "a called-off dial reported a refusal nobody was waiting on")
    }
}
