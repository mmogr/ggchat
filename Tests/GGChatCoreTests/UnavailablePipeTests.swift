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

    /// The list is written out by hand, and that is the whole risk: it is not
    /// `CaseIterable` and there is no switch, so a case added to
    /// `PipeConnectError` and forgotten here ships with no sentence and this
    /// test still passes. Anything added there is added here in the same
    /// commit.
    ///
    /// What it proves differs by case, and three of the five now carry their
    /// own sentence rather than composing one. For `invalidTicket` and
    /// `dialFailed` this says only that the payload is passed through and not
    /// dropped; that the sentence is worth reading is proved where it is
    /// written, in `PairingReaderTests` and `ModelpipeConnectorTests`, which
    /// assert it is not the paste and names no binding type. `pairingRefused`
    /// is here because it does compose — it adds the line naming where the
    /// next attempt starts — and `missingToken` and `unavailable` are the two
    /// written here outright.
    func testEveryRefusalHasASentence() {
        let errors: [PipeConnectError] = [
            .invalidTicket(message: "That is not a ticket."), .missingToken, .unavailable,
            .dialFailed(message: "The other machine did not answer.", retryable: true),
            .pairingRefused(message: "That pairing code was not accepted."),
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }

    /// Retryability is the app's own reading of the refusal, and the three
    /// made before anything is dialled are never worth a second attempt: the
    /// ticket is still wrong, the token is still missing, the build still has
    /// no pipe in it.
    func testOnlyADialThatWasActuallyMadeIsWorthRepeating() {
        XCTAssertFalse(PipeConnectError.invalidTicket(message: "That is not a ticket.").isRetryable)
        XCTAssertFalse(PipeConnectError.missingToken.isRetryable)
        XCTAssertFalse(PipeConnectError.unavailable.isRetryable)
        XCTAssertTrue(
            PipeConnectError.dialFailed(message: "asleep", retryable: true).isRetryable)
        XCTAssertFalse(
            PipeConnectError.dialFailed(message: "not a ticket", retryable: false).isRetryable)
    }
}
