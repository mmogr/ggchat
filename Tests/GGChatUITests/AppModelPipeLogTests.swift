import GGChatCore
import XCTest

@testable import GGChatUI

/// What the app writes to its log on the pipe's paths (#70). `OSLogSink`
/// writes every line as public, so what keeps a credential out of the log is
/// what each line chooses to interpolate, and only a test can check that.
///
/// The connector's own sentences pass through unchanged. What keeps the
/// ticket out of a real one is `ModelpipeConnector.refusal` and
/// modelpipe-ffi's `no_error_renders_the_ticket`; this shows the app adds
/// no credential of its own.
final class AppModelPipeLogTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    /// Spelt to be found: none of them is a word or a number a log line
    /// carries for any other reason.
    private let ticket = "pipe-ticket-qv7zk3-never-logged"
    private let officeTicket = "pipe-ticket-hb5wn1-never-logged"
    private let token = "token-xw4ph9-never-logged"
    private let pairedKey = "paired-key-jm2rt8-never-logged"
    private let codes = ["604217", "931586"]

    /// A dial asked for and refused, the same refusal on a return to the
    /// foreground, a dial that lands, the pipe dropping, a pairing with a new
    /// machine and a pairing again: each writes a line, and no line carries
    /// a ticket, a token, the key a code was traded for, or a code.
    @MainActor
    func testNoPipeOrPairingLineCarriesATicketATokenOrACode() async throws {
        let log = CapturingLogSink()
        let registry = LoopbackProviderRegistry()
        let connector = SwitchedConnector(registry: registry, pairings: MockPairings(outcome: .success(pairedKey)))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AppModelPipeLogTests.\(UUID().uuidString)"))
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: log, registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let home = pipe(named: "home", ticket: ticket)
        try model.addProvider(home, credentials: [.ticket: ticket, .token: token])
        var written = log.lines.count

        await model.connectPipe(for: home)
        XCTAssertNotNil(model.lastError, "the refused dial somebody asked for was not reported")
        model.lastError = nil
        expectMore(log, than: &written, from: "a refused dial")

        await model.scene(.foreground).value
        XCTAssertNil(model.lastError, "the resume's refusal was not a quiet one")
        expectMore(log, than: &written, from: "a quiet refusal on a return to the foreground")

        connector.answer()
        await model.connectPipe(for: home)
        try await Runs.until("the pipe to come up") { model.pipeStatus(for: home.id) == .direct }
        expectMore(log, than: &written, from: "a dial that landed")

        let session = try XCTUnwrap(model.pipeSession(for: home.id) as? MockPipeSession)
        session.dropped()
        try await Runs.until("the pipe to close") { model.pipeStatus(for: home.id) == .closed }
        expectMore(log, than: &written, from: "a pipe the far machine dropped")

        let office = pipe(named: "office", ticket: officeTicket)
        try await model.addPairedProvider(
            office, pairing: "\(officeTicket)-\(codes[0])", ticket: officeTicket, deviceName: "kitchen phone")
        expectMore(log, than: &written, from: "a pairing")

        try await model.updatePairedProvider(home, pairing: "\(ticket)-\(codes[1])", ticket: ticket, deviceName: nil)
        expectMore(log, than: &written, from: "a pairing again")

        for line in log.lines {
            for secret in [ticket, officeTicket, token, pairedKey] + codes {
                XCTAssertFalse(line.contains(secret), "\(secret) in a log line: \(line)")
            }
        }
    }

    private func pipe(named name: String, ticket: String) -> ProviderConfig {
        ProviderConfig(name: name, kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
    }

    /// Fails unless the step just taken wrote at least one line, so the
    /// search below cannot pass over a path that logged nothing.
    private func expectMore(
        _ log: CapturingLogSink, than written: inout Int, from step: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThan(log.lines.count, written, "\(step) wrote no line", file: file, line: line)
        written = log.lines.count
    }
}
