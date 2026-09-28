import XCTest

@testable import GGChatCore

/// What this side says when the other machine is asleep, off or out of reach,
/// and the mock that goes quiet the way modelpipe reports it.
final class QuietMachineTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// `tunnel_unavailable` is written on this device, and written the same
    /// when the other machine is the one that is gone, so its line names
    /// both. A failure saved with the code reads the same line, and the other
    /// code filed on this side keeps the one about this device's connection.
    func testTheTunnelHintNamesTheOtherMachineAsWellAsThisDevice() {
        let sentence = "This device may be offline, or the other machine may be asleep, switched off or out of reach."
        let refusal = ProviderError.server(
            status: 502, code: "tunnel_unavailable", message: "no tunnel to the serving side is connected right now")
        XCTAssertEqual(refusal.hint, sentence)
        XCTAssertEqual(Failure(refusal).hint, sentence, "a saved refusal reads another line")
        XCTAssertEqual(refusal.whereToLook, .connectingSide, "the side that wrote it has not moved")
        XCTAssertEqual(
            ProviderError.hint(forCode: "incomplete_request", on: .connectingSide),
            WhereToLook.connectingSide.hint)
    }

    /// A machine that pins device keys refuses a device it still lists with
    /// the same answer as a wrong code, so the advice says how to take this
    /// device off that list before pairing again.
    func testARefusedPairingSaysToForgetAStillListedDeviceFirst() {
        let refusal = PipeConnectError.pairingRefused(message: "That pairing code was not accepted.")
        XCTAssertEqual(
            refusal.errorDescription,
            "That pairing code was not accepted. Run `gglib remote invite` there again."
                + " If this device is still listed on the other machine, remove it there first with"
                + " `gglib remote forget`, then pair again.")
    }

    /// modelpipe never closes a pipe whose peer went quiet: it goes back to
    /// looking and stays there. The mock's quiet is the same, so a test of
    /// what the app does with a quiet machine is not a test of a close.
    func testAQuietMockGoesBackToLookingAndDoesNotClose() async throws {
        let sleeper = GatedSleeper()
        let connector = MockPipeConnector(sleeper: sleeper, registry: LoopbackProviderRegistry())
        let session = try await connector.connect(ticket: ticket, token: "token")
        let mock = try XCTUnwrap(session as? MockPipeSession)
        var iterator = session.status.makeAsyncIterator()
        _ = await iterator.next()
        await sleeper.release()
        _ = await iterator.next()
        await sleeper.release()
        let connected = await iterator.next()
        XCTAssertEqual(connected, .direct)

        mock.wentQuiet()
        let quiet = await iterator.next()
        XCTAssertEqual(quiet, .idle, "a quiet machine reads as looking")
        XCTAssertEqual(mock.currentStatus, .idle)
        XCTAssertNil(mock.closeReason, "a quiet machine was reported as a close")

        await session.shutdown()
        let closed = await iterator.next()
        XCTAssertEqual(closed, .closed, "something other than the hang-up followed the quiet")
    }
}
