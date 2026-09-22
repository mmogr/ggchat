import GGChatCore
import Modelpipe
import XCTest

@testable import GGChatPipe

/// What a person is shown when a pairing is refused: modelpipe's own sentence,
/// and the line this app adds saying where the next attempt starts.
///
/// A file of its own beside `ModelpipeConnectorPairingTests`, which is what a
/// pairing *does*; together they would be over this repo's file-size limit.
/// The split falls where the seam does — everything here is
/// `ModelpipeConnector.refusal(for:)` turning an `MpPairError` into a
/// `PipeConnectError`, and nothing here dials.
final class ModelpipePairRefusalTests: XCTestCase {
    /// D3: a refused code has somewhere to send the person, so it keeps a
    /// case of its own — and the case is what lets the line naming what to
    /// run on the other machine be added to modelpipe's sentence.
    func testARefusedCodeKeepsItsOwnCaseAndSaysWhereToGetANewOne() async {
        let refusal = ModelpipeConnector.refusal(for: .Refused)

        guard case .pairingRefused(let message) = refusal else {
            return XCTFail("a refused code was reported as something else: \(refusal)")
        }
        XCTAssertEqual(message, MpPairError.Refused.message(), "the sentence was written here instead of upstream")
        XCTAssertTrue(
            refusal.localizedDescription.contains("gglib remote invite"),
            "nothing told the person where the next attempt starts: \(refusal.localizedDescription)")
        XCTAssertFalse(refusal.isRetryable, "a spent code was offered as worth retrying")
    }

    /// #113: a desktop on gglib 0.18 pairs another way. Its edge spends the
    /// code and its proxy has no such route, so the pairing request arrives
    /// at a router that has never heard of it and is answered `404`. Asking
    /// that desktop for another code before updating it spends that one too,
    /// so the person is told to update it first. The status and the sentence
    /// are spelt out here, not read from the source.
    func testADesktopTooOldToPairSaysToUpdateItAndThatTheCodeIsSpent() {
        let error = MpPairError.UnexpectedStatus(status: 404)
        let refusal = ModelpipeConnector.refusal(for: error)

        XCTAssertEqual(refusal, .desktopTooOldToPair(message: error.message()))
        XCTAssertEqual(
            refusal.errorDescription,
            "The other machine answered the pairing request with HTTP 404, which is not a pairing answer."
                + " It is probably running a version too old to pair this way."
                + " The code has been spent."
                + " Update gglib there to a version newer than 0.18, then run `gglib remote invite` for a new code.")
        XCTAssertFalse(refusal.isRetryable, "a spent code was offered as worth retrying")
    }

    /// A status nobody has traced to a mechanism is not blamed on a version:
    /// sending somebody to update a desktop that may already be current
    /// wastes their time. Every status but `404` gets the line that says only
    /// what is known, that the code may be gone.
    ///
    /// `410` rather than a neighbour of 404, so a mapping written as a range
    /// rather than an equality fails here.
    func testAStatusOtherThanNotFoundIsNotBlamedOnTheDesktopsVersion() {
        let error = MpPairError.UnexpectedStatus(status: 410)
        let refusal = ModelpipeConnector.refusal(for: error)

        XCTAssertEqual(refusal, .unexpectedAnswer(message: error.message()))
        XCTAssertEqual(
            refusal.errorDescription,
            "The other machine answered the pairing request with HTTP 410, which is not a pairing answer."
                + " The code may have been spent, so run `gglib remote invite` there for a new one.")
        XCTAssertFalse(
            refusal.localizedDescription.contains("0.18"),
            "an unexplained status sent the person after a version: \(refusal.localizedDescription)")
        XCTAssertFalse(refusal.isRetryable, "an answer nobody gets past by trying again was offered a retry")
    }

    /// An answer carrying no status at all — a `200` whose body this side
    /// could not read as a pairing answer — keeps modelpipe's sentence and
    /// adds only what is known: the code may be gone.
    func testAnyOtherAnswerThatIsNotAPairingAnswerSaysTheCodeMayBeSpent() {
        let error = MpPairError.Unexpected(detail: "an empty key or device")
        let refusal = ModelpipeConnector.refusal(for: error)

        XCTAssertEqual(refusal, .unexpectedAnswer(message: error.message()))
        XCTAssertEqual(
            refusal.errorDescription,
            "The other machine's answer was not a pairing answer (an empty key or device)."
                + " The code may have been spent, so run `gglib remote invite` there for a new one.")
        XCTAssertFalse(refusal.isRetryable, "an answer nobody gets past by trying again was offered a retry")
    }

    /// The mapping is exhaustive and written out rather than looped, so a
    /// case modelpipe adds is a compile error rather than a sentence nobody
    /// wrote. What every case owes is a sentence with none of the binding's
    /// own rendering in it: `MpPairError.errorDescription` is
    /// `String(reflecting:)`, so one allowed through unmapped puts
    /// `modelpipe_ffi.MpPairError.Unreached(why: …)` on a person's screen.
    func testEveryPairingErrorArrivesAsASentenceAndNotADebugRendering() {
        let errors: [MpPairError] = [
            .NoCode,
            .BadPairingString(reason: "the part before the code is not a ticket"),
            .Dial(reason: "the port is taken", retryable: true),
            .Unreached(why: .TimedOut(withinMs: 150)),
            .Refused,
            .Exchange(reason: "the connection was reset"),
            .Unexpected(detail: "no api_key"),
            .UnexpectedStatus(status: 404),
            .Unknown(detail: "Grown(…)"),
        ]
        for error in errors {
            let sentence = ModelpipeConnector.refusal(for: error).errorDescription ?? ""
            XCTAssertFalse(sentence.isEmpty, "\(error) has nothing to say")
            XCTAssertFalse(sentence.contains("MpPairError"), sentence)
            // The module is `Modelpipe`, so `String(reflecting:)` renders
            // `Modelpipe.MpPairError…`. Looking for `modelpipe_ffi`, the Rust
            // crate's name, is an assertion that can never fire.
            XCTAssertFalse(sentence.contains("Modelpipe."), sentence)
            XCTAssertTrue(sentence.contains(error.message()), "the sentence is not the binding's: \(sentence)")
        }
    }

    /// A machine that was asleep may answer next time, and the binding is the
    /// thing that knows which pairing failures are like that.
    func testThePairingRetryabilityIsTheBindings() {
        let unreached = MpPairError.Unreached(why: .TimedOut(withinMs: 150))
        XCTAssertEqual(
            ModelpipeConnector.refusal(for: unreached).isRetryable, unreached.isRetryable(),
            "retryability was decided here instead of being carried from the binding")
        XCTAssertTrue(unreached.isRetryable(), "the binding now calls a timed-out pairing not worth repeating")
    }

    /// The arms that answer `false` outright rather than asking the binding
    /// do so because these are failures nobody gets past by trying again: a
    /// string with no code in it, a string that is not a pairing string, and
    /// an answer that was not a pairing answer — carrying a status this side
    /// explains, one it does not, or no status at all. Those arms and the
    /// binding agree today and no test can tell
    /// them apart on that, so what this pins is the agreement — a release
    /// that changes its mind fails here, at the release that changes it,
    /// rather than quietly offering a retry that cannot work.
    func testTheFailuresNoRetryCanFixAgreeWithTheBinding() {
        let hopeless: [MpPairError] = [
            .NoCode,
            .BadPairingString(reason: "the part before the code is not a ticket"),
            .Unexpected(detail: "no api_key"),
            .UnexpectedStatus(status: 404),
            .UnexpectedStatus(status: 410),
        ]
        for error in hopeless {
            XCTAssertEqual(
                ModelpipeConnector.refusal(for: error).isRetryable, error.isRetryable(),
                "retryability was decided here instead of being carried from the binding: \(error)")
            XCTAssertFalse(
                error.isRetryable(),
                "the binding now calls this worth repeating: revisit the arm the case sits in")
        }
    }
}
