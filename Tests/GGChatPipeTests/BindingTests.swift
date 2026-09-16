import GGChatCore
import GGChatPipe
import Modelpipe
import XCTest

/// That the binding is really here, and that its four status values still mean
/// what this app thinks they mean.
///
/// The link is the point of the first test. Everything else in this repository
/// is Swift compiled from source; `Modelpipe` is a binary xcframework fetched
/// at resolve time and checked against a uniffi checksum that is only verified
/// on first use. A mismatched pair does not fail the build — it traps at the
/// first call, on a device, in front of a person. So something has to make a
/// call across the boundary on every CI run, and this is it.
final class BindingTests: XCTestCase {
    /// A ticket the far side never has to see refused, because it is refused
    /// here. Reaching this error means the Rust ran: the string crossed the
    /// boundary, a `uniffi` error came back, and it arrived as a Swift enum.
    func testTheBindingIsLinkedAndAnswersAcrossTheBoundary() async {
        do {
            _ = try await mpConnect(ticket: "not-a-ticket", options: MpConnectOptions())
            XCTFail("a string that is not a ticket was accepted as one")
        } catch let error as MpError {
            guard case .BadTicket = error else {
                return XCTFail("expected BadTicket, got \(error.message())")
            }
            XCTAssertFalse(
                error.message().isEmpty,
                "an error the app may have to show a person came back with nothing to say")
        } catch {
            XCTFail("the binding threw something that is not an MpError: \(error)")
        }
    }

    /// Pairing waits for the far machine before it spends the code, and this
    /// is the real `mpPair` proving it offline.
    ///
    /// The ticket is modelpipe's normative vector 1, which names an endpoint
    /// that does not exist; discovery is off so nothing is asked of the
    /// network beyond the relay dial, and the wait is 150 ms so the test
    /// costs a fraction of a second. Reaching `Unreached` means the string
    /// parsed, a pipe was dialled, the wait ran out — and the code was never
    /// presented. A redeem sent into that gap is answered `502` by the
    /// tunnel's own edge, which spends the one-time code on nothing and needs
    /// a fresh `gglib remote invite`.
    func testPairingWaitsForTheFarMachineBeforeSpendingTheCode() async {
        let vector = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
        var options = MpConnectOptions()
        options.discovery = false
        do {
            _ = try await mpPair(
                pairing: "\(vector)-483920", label: "a test", options: options, reachWithinMs: 150)
            XCTFail("a machine that does not exist accepted a pairing code")
        } catch let error as MpPairError {
            guard case .Unreached = error else {
                return XCTFail("expected Unreached, got \(error.message())")
            }
            XCTAssertTrue(
                error.isRetryable(),
                "a machine that did not answer in time is one that may answer next time")
            XCTAssertFalse(
                error.message().isEmpty,
                "an error the app has to show a person came back with nothing to say")
        } catch {
            XCTFail("the binding threw something that is not an MpPairError: \(error)")
        }
    }

    /// The two enums match one for one, and this is what keeps that true. It
    /// is written out rather than looped so that a case added on either side
    /// is a compile error here and not a silent gap.
    func testEveryPipeStatusCrossesUnchanged() {
        XCTAssertEqual(PipeStatus(MpPipeStatus.idle), .idle)
        XCTAssertEqual(PipeStatus(MpPipeStatus.relayed), .relayed)
        XCTAssertEqual(PipeStatus(MpPipeStatus.direct), .direct)
        XCTAssertEqual(PipeStatus(MpPipeStatus.closed), .closed)
    }

    /// `isConnected` is the app's own judgement, not the binding's, and the
    /// pipe path depends on relayed counting as connected: a relayed pipe
    /// works, and its traffic is no more readable than a direct one's.
    func testARelayedPipeCountsAsConnected() {
        XCTAssertTrue(PipeStatus(MpPipeStatus.relayed).isConnected)
        XCTAssertTrue(PipeStatus(MpPipeStatus.direct).isConnected)
        XCTAssertFalse(PipeStatus(MpPipeStatus.idle).isConnected)
        XCTAssertFalse(PipeStatus(MpPipeStatus.closed).isConnected)
    }
}
