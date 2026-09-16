import XCTest

@testable import GGChatCore

final class TicketTests: XCTestCase {
    /// modelpipe's normative vector 1 (`docs/ticket-format-v0.md`): the
    /// shortest string that is a ticket, 67 characters, generated from the
    /// RFC 8032 §7.1 test key. `ticket_vectors.py` has no `--update` flag on
    /// purpose — the vectors cannot drift — so this is safe to hard-code.
    static let minimalTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// The seven shape tests that were here went with `Ticket.validateShape`:
    /// modelpipe reads a ticket now, and `PairingReaderTests` holds the
    /// vectors it is read against. What is left is the one thing this app
    /// does to a ticket that modelpipe does not — fingerprint it.
    func testDigestIgnoresCaseAndIsNotTheTicket() {
        let lower = Self.minimalTicket
        let digest = Ticket.digest(lower)
        XCTAssertEqual(digest, Ticket.digest(lower.uppercased()))
        XCTAssertEqual(digest.count, 16)
        XCTAssertFalse(lower.contains(digest))
        XCTAssertNotEqual(digest, Ticket.digest("pipe" + String(repeating: "z", count: 63)))
    }
}
