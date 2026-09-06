import XCTest

@testable import GGChatCore

final class UnavailablePipeTests: XCTestCase {
    /// modelpipe's normative vector 1 from `docs/ticket-format-v0.md`: a real
    /// ticket, so this asserts about the build and not about the input.
    private let realTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    func testABuildWithNoPipeRefusesAGoodTicketInsteadOfMockingOne() async {
        do {
            _ = try await UnavailablePipeConnector().connect(ticket: realTicket, token: "a-real-token")
            XCTFail("a build with no pipe handed back a session")
        } catch let error as PipeConnectError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("\(error)")
        }
    }

    /// The user pasted something correct, so the sentence must not send them
    /// back to the ticket or the token to fix what is not broken.
    func testTheRefusalIsASentenceThatBlamesTheBuildAndNotTheUser() throws {
        let sentence = try XCTUnwrap(PipeConnectError.unavailable.errorDescription)
        XCTAssertTrue(sentence.hasSuffix("."), sentence)
        XCTAssertTrue(sentence.contains("build"), sentence)
        XCTAssertFalse(sentence.lowercased().contains("ticket"), sentence)
        XCTAssertFalse(sentence.lowercased().contains("token"), sentence)
    }

    func testEveryRefusalHasASentence() {
        let errors: [PipeConnectError] = [.invalidTicket(.badPrefix), .missingToken, .unavailable]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }
}
