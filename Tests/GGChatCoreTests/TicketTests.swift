import XCTest

@testable import GGChatCore

final class TicketTests: XCTestCase {
    /// modelpipe's normative vector 1 (`docs/ticket-format-v0.md`): the
    /// shortest string that is a ticket, 67 characters, generated from the
    /// RFC 8032 §7.1 test key. `ticket_vectors.py` has no `--update` flag on
    /// purpose — the vectors cannot drift — so this is safe to hard-code.
    static let minimalTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// A body far too short to be one, for the checks that refuse before
    /// length is ever considered.
    private let body16 = "abcdefghijklmnop"

    private func check(_ ticket: String) -> TicketShapeError? {
        if case .failure(let error) = Ticket.validateShape(ticket) { return error }
        return nil
    }

    func testLowercaseUppercaseAndMixedCaseAreAccepted() {
        XCTAssertNil(check(Self.minimalTicket))
        XCTAssertNil(check(Self.minimalTicket.uppercased()))
        XCTAssertNil(check("PiPe" + String(repeating: "aBcDeFgH", count: 7) + "234567a"))
    }

    func testLongestPossibleTicketIsAcceptedAndOneMoreIsNot() {
        let longest = "pipe" + String(repeating: "a", count: Ticket.maximumBodyLength)
        XCTAssertEqual(longest.count, 1643)
        XCTAssertNil(check(longest))
        XCTAssertEqual(check(longest + "a"), .tooLong(count: 1644))
    }

    /// The two real lengths. 67 is modelpipe's normative minimum — one
    /// endpoint id, no addresses — and 81 is what a live `modelpipe serve`
    /// printed on 6 Sep 2026: a 77-character body, 5 mod 8, carrying
    /// addresses as well.
    func testTheShapeARealTicketHas() {
        XCTAssertEqual(Self.minimalTicket.count, Ticket.minimumLength)
        XCTAssertEqual(Self.minimalTicket.count, 67)
        XCTAssertNil(check(Self.minimalTicket))

        let body = String(repeating: "abcdefgh", count: 9) + "abcde"
        XCTAssertEqual(body.count, 77)
        let ticket = "pipe" + body
        XCTAssertEqual(ticket.count, 81)
        XCTAssertNil(check(ticket))
        XCTAssertNil(check(ticket.uppercased()), "a QR scan gives it in uppercase")
        XCTAssertEqual(Ticket.normalized(ticket.uppercased()), ticket)
    }

    /// The floor is its own rule, not a side effect of the base32 remainder:
    /// 59 characters is a legal padding-free encoding and still cannot be
    /// carrying a 32-byte endpoint id. A ticket cut short by a chat client's
    /// line wrap is the way this actually arrives, and it used to be
    /// accepted, dialled, and left to fail somewhere further in.
    func testATicketTooShortToCarryAnEndpointIdIsRefused() {
        let shortBody = String(repeating: "a", count: 55)
        XCTAssertEqual(shortBody.count % 8, 7, "55 is a length padding-free base32 can produce")
        XCTAssertEqual(check("pipe" + shortBody), .badLength(count: 59))

        let truncated = String(Self.minimalTicket.dropLast())
        XCTAssertEqual(check(truncated), .badLength(count: 66))
        XCTAssertEqual(check("pipeab"), .badLength(count: 6))
    }

    func testNonASCIIIsRejectedBeforeCaseFolding() {
        XCTAssertEqual(check("pipé" + body16), .nonASCII)
        XCTAssertEqual(check(Self.minimalTicket + "ß"), .nonASCII)
    }

    func testPrefixPaddingAlphabetAndLength() {
        XCTAssertEqual(check(""), .empty)
        XCTAssertEqual(check("pip3" + body16), .badPrefix)
        XCTAssertEqual(check("pipe"), .badLength(count: 4))
        XCTAssertEqual(check("pipeabc="), .padding)
        // Which character, before how many: a short string with a character
        // outside the alphabet is better described by the character.
        XCTAssertEqual(check("pipeab1d"), .badCharacter(offset: 6))
        XCTAssertEqual(check("pipeab0d"), .badCharacter(offset: 6))
        XCTAssertEqual(check("pipeabc"), .badLength(count: 7))
    }

    func testEveryErrorHasASentence() {
        let errors: [TicketShapeError] = [
            .empty, .nonASCII, .badPrefix, .badCharacter(offset: 4), .padding, .tooLong(count: 2000),
            .badLength(count: 7),
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }

    func testDigestIgnoresCaseAndIsNotTheTicket() {
        let lower = Self.minimalTicket
        let digest = Ticket.digest(lower)
        XCTAssertEqual(digest, Ticket.digest(lower.uppercased()))
        XCTAssertEqual(digest.count, 16)
        XCTAssertFalse(lower.contains(digest))
        XCTAssertNotEqual(digest, Ticket.digest("pipe" + String(repeating: "z", count: 63)))
    }
}
