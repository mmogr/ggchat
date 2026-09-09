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
