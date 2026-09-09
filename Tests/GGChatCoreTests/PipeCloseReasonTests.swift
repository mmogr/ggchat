import XCTest

@testable import GGChatCore

/// The third case, and the rule about which closes are worth a person's
/// attention.
final class PipeCloseReasonTests: XCTestCase {
    /// Over `allCases`, so a fourth reason added later cannot be added
    /// without deciding what it says.
    func testEveryReasonThatWasNotAskedForHasASentenceNamingASide() {
        for reason in PipeCloseReason.allCases where reason.wasUnexpected {
            let sentence = reason.sentence(naming: "Home")
            XCTAssertNotNil(sentence, "\(reason) is unexpected and has nothing to tell anyone")
            XCTAssertTrue(
                sentence?.contains("Home") == true || sentence?.contains("This device") == true,
                "\(reason) does not name a side to look at: \(sentence ?? "nil")")
            XCTAssertTrue(sentence?.hasSuffix(".") == true, "\(reason) is not a sentence")
        }
    }

    /// The silence that keeps a walk to the background quiet.
    ///
    /// Every hang-up the app performs — the background, a manual reconnect, a
    /// provider deleted — arrives here, and each one is something the person
    /// just did. An alert about it would be the app reporting the user's own
    /// action back to them.
    func testAHangUpThisAppAskedForIsNotWorthASentence() {
        XCTAssertFalse(PipeCloseReason.shutdown.wasUnexpected)
        XCTAssertNil(PipeCloseReason.shutdown.sentence(naming: "Home"))
    }

    /// The two unexpected reasons send a person to different places, so they
    /// must not read the same.
    func testTheTwoUnexpectedReasonsBlameDifferentSides() {
        let vanished = PipeCloseReason.peerVanished.sentence(naming: "Home")
        let listener = PipeCloseReason.listenerFailed.sentence(naming: "Home")

        XCTAssertEqual(vanished, "Home stopped answering.")
        XCTAssertEqual(listener, "This device stopped accepting the connection to Home.")
        XCTAssertNotEqual(vanished, listener)
    }
}
