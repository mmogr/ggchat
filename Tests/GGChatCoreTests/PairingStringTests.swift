import XCTest

@testable import GGChatCore

final class PairingStringTests: XCTestCase {
    /// modelpipe's normative vector 1 from `docs/ticket-format-v0.md`: a real
    /// ticket, so these assert about the splitter and not about the input.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    private func parsed(_ input: String) -> PairingString? {
        guard case .success(let value) = PairingString.parse(input) else { return nil }
        return value
    }

    private func failure(_ input: String) -> PairingStringError? {
        guard case .failure(let error) = PairingString.parse(input) else { return nil }
        return error
    }

    func testATicketAndACodeComeApartOnTheLastHyphen() throws {
        let split = try XCTUnwrap(parsed("\(ticket)-483920"))
        XCTAssertEqual(split.ticket, ticket)
        XCTAssertEqual(split.code, "483920")
    }

    func testABareTicketHasNoCodeAndStillParses() throws {
        let split = try XCTUnwrap(parsed(ticket))
        XCTAssertEqual(split.ticket, ticket)
        XCTAssertNil(split.code)
        XCTAssertEqual(split.canonical, ticket)
    }

    /// The one string the system prints: gglib's QR payload is the whole
    /// pairing string uppercased, because uppercase base32 is a QR
    /// alphanumeric payload and lowercase is not.
    func testTheOneStringGGLibPrintsIsAccepted() throws {
        let printed = "\(ticket)-483920".uppercased()
        let split = try XCTUnwrap(parsed(printed))
        XCTAssertEqual(split.ticket, ticket, "the canonical form is lowercase")
        XCTAssertEqual(split.code, "483920")
        XCTAssertEqual(split.canonical, "\(ticket)-483920")
        XCTAssertNotNil(parsed(split.canonical), "what it hands back, it accepts again")
    }

    func testASuffixThatIsNotSixDigitsIsNamedAsTheProblem() throws {
        XCTAssertEqual(failure("\(ticket)-48392"), .suffixIsNotACode)
        XCTAssertEqual(failure("\(ticket)-4839201"), .suffixIsNotACode)
        XCTAssertEqual(failure("\(ticket)-abcdef"), .suffixIsNotACode)
        XCTAssertEqual(failure("\(ticket)-"), .suffixIsNotACode)
        XCTAssertEqual(
            failure("\(ticket)-４８３９２０"), .suffixIsNotACode,
            "six digit-shaped characters are not six digits; the far machine compares bytes")
        let sentence = try XCTUnwrap(PairingStringError.suffixIsNotACode.errorDescription)
        XCTAssertTrue(sentence.contains("6-digit"), sentence)
    }

    /// The form shows this sentence under the field, so it has to be the
    /// ticket's own complaint rather than a second-hand summary of it.
    func testAPairingStringThatIsNotOneKeepsTheTicketsOwnSentence() throws {
        XCTAssertEqual(failure("nope"), .badTicket(.badPrefix))
        XCTAssertEqual(failure("nope")?.errorDescription, TicketShapeError.badPrefix.errorDescription)
        XCTAssertEqual(
            failure("not-a-ticket-123456"), .badTicket(.badPrefix),
            "the split happens first, so the part before the code is what is judged")
        XCTAssertEqual(failure("pipeab1d"), .badTicket(.badCharacter(offset: 6)))
    }

    func testBlankIsRefusedWithTheShapeToType() throws {
        XCTAssertEqual(failure(""), .empty)
        XCTAssertEqual(failure("   \n"), .empty)
        let sentence = try XCTUnwrap(PairingStringError.empty.errorDescription)
        XCTAssertTrue(sentence.contains("ticket-code"), sentence)
    }

    func testSurroundingWhitespaceIsForgiven() throws {
        let split = try XCTUnwrap(parsed("  \(ticket)-483920\n"))
        XCTAssertEqual(split.code, "483920")
        XCTAssertEqual(split.ticket, ticket)
    }

    func testEveryRefusalHasASentence() {
        let errors: [PairingStringError] = [.empty, .suffixIsNotACode, .badTicket(.padding)]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }
}
