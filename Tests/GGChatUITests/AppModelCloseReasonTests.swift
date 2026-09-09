import GGChatCore
import XCTest

@testable import GGChatUI

/// A close that nobody asked for arrives with a reason beside it, and says so
/// once. A close the app performed says nothing at all.
final class AppModelCloseReasonTests: XCTestCase {
    /// modelpipe's normative vector 1, the shortest string that is a ticket.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel() throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelCloseReasonTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "Home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted {
            await Task.yield()
        }
    }

    /// The reason lands with the status, not after it — they are one event,
    /// and a screen reading one without the other would be describing half of
    /// what happened.
    @MainActor
    func testAPeerThatVanishesLeavesAReasonBesideTheStatusAndOneSentence() async throws {
        let (model, config) = try makeModel()
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertNil(model.pipeCloseReason(for: config.id), "an open pipe has nothing to explain")
        XCTAssertNil(model.lastError)

        let session = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        session.dropped()
        await waitForStatus(.closed, model, config.id)

        XCTAssertEqual(model.pipeCloseReason(for: config.id), .peerVanished)
        XCTAssertEqual(
            model.lastError, "Home stopped answering.",
            "a machine that stopped answering is worth telling the person about")
    }

    /// Every hang-up the app performs comes through here: the background, a
    /// provider deleted, a reconnect the person pressed. None of them is news.
    @MainActor
    func testAHangUpTheAppPerformedExplainsNothingAndSaysNothing() async throws {
        let (model, config) = try makeModel()
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)

        await model.disconnectPipe(for: config.id, leaving: .closed)

        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)
        XCTAssertNil(
            model.pipeCloseReason(for: config.id),
            "a close this app asked for has no reason to carry")
        XCTAssertNil(model.lastError, "an alert here would report the person's own action back to them")
    }

    /// A reason describes the close on screen or it describes nothing. Dialling
    /// again must not leave the last failure's sentence attached to a pipe that
    /// is now up.
    @MainActor
    func testDiallingAgainClearsTheReasonTheLastCloseLeft() async throws {
        let (model, config) = try makeModel()
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        let session = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        session.dropped()
        await waitForStatus(.closed, model, config.id)
        XCTAssertEqual(model.pipeCloseReason(for: config.id), .peerVanished)

        model.lastError = nil
        await model.reconnectPipe(for: config)
        await waitForStatus(.direct, model, config.id)

        XCTAssertNil(
            model.pipeCloseReason(for: config.id),
            "a pipe that is up must not still be carrying the reason it went down")
    }
}
