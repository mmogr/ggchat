import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A connector that refuses with a sentence of its own, or hangs until it is
/// let go, so a dial can be cancelled while it is out.
private final class SlowRefusingConnector: PipeConnector {
    private let held = Mutex(true)
    private let dials = Mutex(0)

    let refusal: PipeConnectError

    init(refusal: PipeConnectError = .dialFailed(message: "The port is taken.", retryable: true)) {
        self.refusal = refusal
    }

    var dialCount: Int { dials.withLock { $0 } }

    func release() { held.withLock { $0 = false } }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        dials.withLock { $0 += 1 }
        while held.withLock({ $0 }) {
            try Task.checkCancellation()
            await Task.yield()
        }
        throw refusal
    }
}

/// A connector that hands back a session whose status stream can be ended on
/// demand, which is what a pipe dying quietly looks like from up here.
private final class ClosableConnector: PipeConnector {
    let sessions = Mutex<[ClosableSession]>([])

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        let session = ClosableSession()
        sessions.withLock { $0.append(session) }
        return session
    }
}

private final class ClosableSession: PipeSession, Sendable {
    let baseURL = URL(string: "http://127.0.0.1:51999/v1")!
    private let relay = PipeStatusRelay(initial: .direct)

    var status: AsyncStream<PipeStatus> { relay.stream() }

    /// The far side went away and the pipe ended its own stream.
    func die() {
        relay.send(.closed)
        relay.finish()
    }

    func shutdown() async {
        relay.send(.closed)
        relay.finish()
    }
}

/// What a dial does *not* do: shout about a failure nobody asked for, and
/// leave a dead session in place of one that could be dialled again.
final class AppModelQuietDialTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(dialling connector: any PipeConnector) throws -> (AppModel, ProviderConfig) {
        let defaults = UserDefaults(suiteName: "AppModelQuietDialTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            registry: LoopbackProviderRegistry(), pipeConnector: connector,
            diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    /// A dial the person asked for says why it failed.
    @MainActor
    func testADialSomebodyAskedForSaysWhatWentWrong() async throws {
        let connector = SlowRefusingConnector()
        let (model, config) = try makeModel(dialling: connector)
        connector.release()

        await model.connectPipe(for: config)

        XCTAssertEqual(model.lastError, "The port is taken.")
    }

    /// A resume dials every pipe it is holding none of. A machine that is
    /// asleep would otherwise raise a modal alert on every single return to
    /// the foreground — including dismissing Control Center, which reaches
    /// the same handler — and with several providers only the last sentence
    /// would survive, because each overwrites the one before it.
    @MainActor
    func testAResumeThatFindsTheMachineAsleepSaysNothing() async throws {
        let connector = SlowRefusingConnector()
        let (model, config) = try makeModel(dialling: connector)
        connector.release()

        await model.connectPipe(for: config)
        XCTAssertNotNil(model.lastError, "the dial the person asked for stayed quiet")
        model.lastError = nil

        await model.didBecomeActive()

        XCTAssertEqual(connector.dialCount, 2, "the resume did not retry")
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed, "the pill is still the way back")
        XCTAssertNil(model.lastError, "a resume nobody asked for raised an alert")
    }

    /// `Composer` dials inside a `.task(id:)` that SwiftUI cancels on every
    /// provider switch. A real connector throws `CancellationError` there,
    /// and reporting it shows the person
    /// "The operation couldn't be completed. (Swift.CancellationError error 1.)"
    /// for having tapped a different conversation.
    @MainActor
    func testADialCancelledByTheViewGoingAwaySaysNothing() async throws {
        let connector = SlowRefusingConnector()
        let (model, config) = try makeModel(dialling: connector)

        let dial = Task { await model.connectPipe(for: config) }
        for _ in 0..<200 where connector.dialCount == 0 { await Task.yield() }
        dial.cancel()
        await dial.value

        XCTAssertNil(model.lastError, "a cancelled dial complained to the person who cancelled it")
        XCTAssertEqual(
            model.pipeStatus(for: config.id), .closed,
            "a cancelled dial still has to leave a pill to press")
    }

    /// A pipe that dies quietly used to leave its dead session installed, and
    /// every route back asks for a dial only when there is none: the
    /// composer's task, and the resume. So the only way out was a manual
    /// press of the pill, for a pipe the app already knew had closed.
    @MainActor
    func testASessionThatEndedIsForgottenSoAResumeCanDialAgain() async throws {
        let connector = ClosableConnector()
        let (model, config) = try makeModel(dialling: connector)

        await model.connectPipe(for: config)
        XCTAssertNotNil(model.pipeSession(for: config.id))

        connector.sessions.withLock { $0.last }?.die()
        for _ in 0..<500 where model.pipeSession(for: config.id) != nil { await Task.yield() }

        XCTAssertNil(
            model.pipeSession(for: config.id),
            "the dead session is still installed, so nothing will dial again")
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)

        await model.didBecomeActive()
        XCTAssertNotNil(
            model.pipeSession(for: config.id), "the resume did not bring the pipe back")
    }

    /// The generation guard: a session that ends after a newer dial has
    /// installed its own must not remove it.
    @MainActor
    func testAnOldSessionEndingDoesNotRemoveTheOneThatReplacedIt() async throws {
        let connector = ClosableConnector()
        let (model, config) = try makeModel(dialling: connector)

        await model.connectPipe(for: config)
        let first = connector.sessions.withLock { $0.first }
        await model.reconnectPipe(for: config)
        XCTAssertEqual(connector.sessions.withLock { $0.count }, 2)

        first?.die()
        for _ in 0..<200 { await Task.yield() }

        XCTAssertNotNil(
            model.pipeSession(for: config.id),
            "an old session ending took the live one down with it")
    }
}
