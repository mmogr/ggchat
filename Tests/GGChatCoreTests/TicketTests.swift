import XCTest

@testable import GGChatCore

final class TicketTests: XCTestCase {
    private let body16 = "abcdefghijklmnop"

    private func check(_ ticket: String) -> TicketShapeError? {
        if case .failure(let error) = Ticket.validateShape(ticket) { return error }
        return nil
    }

    func testLowercaseUppercaseAndMixedCaseAreAccepted() {
        XCTAssertNil(check("pipe" + body16))
        XCTAssertNil(check("PIPE" + body16.uppercased()))
        XCTAssertNil(check("PiPe" + "aBcDeFgH234567ab"))
    }

    func testLongestPossibleTicketIsAcceptedAndOneMoreIsNot() {
        let longest = "pipe" + String(repeating: "a", count: Ticket.maximumBodyLength)
        XCTAssertEqual(longest.count, 1643)
        XCTAssertNil(check(longest))
        XCTAssertEqual(check(longest + "a"), .tooLong(count: 1644))
    }

    func testNonASCIIIsRejectedBeforeCaseFolding() {
        XCTAssertEqual(check("pipé" + body16), .nonASCII)
        XCTAssertEqual(check("pipe" + body16 + "ß"), .nonASCII)
    }

    func testPrefixPaddingAlphabetAndLength() {
        XCTAssertEqual(check(""), .empty)
        XCTAssertEqual(check("pip3" + body16), .badPrefix)
        XCTAssertEqual(check("pipe"), .badLength(count: 4))
        XCTAssertEqual(check("pipeabc="), .padding)
        XCTAssertEqual(check("pipeab1d"), .badCharacter(offset: 6))
        XCTAssertEqual(check("pipeab0d"), .badCharacter(offset: 6))
        XCTAssertEqual(check("pipeabc"), .badLength(count: 7))
        XCTAssertNil(check("pipeab"))
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
        let lower = "pipe" + body16
        let digest = Ticket.digest(lower)
        XCTAssertEqual(digest, Ticket.digest(lower.uppercased()))
        XCTAssertEqual(digest.count, 16)
        XCTAssertFalse(lower.contains(digest))
        XCTAssertNotEqual(digest, Ticket.digest("pipe" + "zzzzzzzzzzzzzzzz"))
    }
}
