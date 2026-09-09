import GGChatCore
import Modelpipe
import XCTest

@testable import GGChatPipe

/// The session's three obligations to everything above the seam: the status
/// stream says the current value first, a close is always written, and
/// shutting down twice is fine.
/// Collects statuses until `stop` values have arrived, so a test never waits
/// on a stream that has already said everything it will say.
///
/// A free function rather than a method: it is called from inside a `Task`,
/// and capturing an `XCTestCase` there is a data race the compiler refuses.
private func collect(_ session: any PipeSession, upTo stop: Int) async -> [PipeStatus] {
    var seen: [PipeStatus] = []
    for await status in session.status {
        seen.append(status)
        if seen.count == stop { break }
    }
    return seen
}

final class ModelpipeSessionTests: XCTestCase {

    func testTheCurrentValueComesFirstEvenToALateSubscriber() async throws {
        let session = try ModelpipeSession(
            pipe: FakePipe(from: .direct), sleeper: ImmediateSleeper(),
            grace: .milliseconds(1))
        let first = await collect(session, upTo: 1)
        XCTAssertEqual(first, [.direct], "a subscriber was told nothing until something changed")
    }

    /// A pipe that dies on its own ends the binding's sequence without ever
    /// saying `closed`. Nothing above the seam writes a status when a stream
    /// merely finishes, so without this the pill keeps reading "Direct" over
    /// a listener that is gone.
    func testAPipeThatDiesOnItsOwnStillSaysClosed() async throws {
        let session = try ModelpipeSession(
            pipe: FakePipe(walk: [.direct], from: .idle, reason: .listenerFailed),
            sleeper: ImmediateSleeper(), grace: .milliseconds(1))

        var seen: [PipeStatus] = []
        for await status in session.status { seen.append(status) }

        XCTAssertEqual(seen.last, .closed, "the stream ended without a close: \(seen)")
        XCTAssertTrue(seen.contains(.direct))
    }

    /// The walk a hole punch actually produces is idle, then relayed for a
    /// second, then direct. Showing "Relayed" for that second reads as a
    /// warning about a connection still being made, so it is held back.
    func testRelayedDoesNotFlashWhenDirectIsAMomentBehindIt() async throws {
        let gate = GatedSleeper()
        let session = try ModelpipeSession(
            pipe: FakePipe(walk: [.relayed, .direct], from: .idle), sleeper: gate,
            grace: .seconds(1))

        var seen: [PipeStatus] = []
        for await status in session.status { seen.append(status) }

        XCTAssertFalse(
            seen.contains(.relayed),
            "relayed was shown even though direct followed within the grace: \(seen)")
        XCTAssertEqual(seen, [.idle, .direct, .closed])
    }

    /// The other half of the same rule: a pipe that really is relayed has to
    /// say so, or the status pill would never report the path the traffic is
    /// actually taking.
    func testRelayedIsShownWhenNothingBetterFollows() async throws {
        let gate = GatedSleeper()
        let session = try ModelpipeSession(
            pipe: FakePipe(walk: [.relayed], from: .idle, stayOpen: true), sleeper: gate,
            grace: .seconds(1))

        // Subscribed before the gate opens, so the deferred publish cannot
        // land before anything is listening. The relay buffers, so what
        // arrives after this line is still delivered in order.
        let stream = session.status
        await gate.release()

        var seen: [PipeStatus] = []
        for await status in stream {
            seen.append(status)
            if seen.count == 2 { break }
        }
        XCTAssertEqual(seen, [.idle, .relayed])
    }

    /// A base URL is not merely something `URL(string:)` accepts. It parses
    /// strings with spaces and no scheme, so the check is the shape the seam
    /// promises: loopback, http, and a port.
    func testAnAddressOffLoopbackIsRefused() {
        for address in ["not a url at all", "http://example.com:8080/v1", "https://127.0.0.1/v1"] {
            XCTAssertThrowsError(
                try ModelpipeSession(
                    pipe: FakePipe(baseUrl: address), sleeper: ImmediateSleeper(),
                    grace: .milliseconds(1)),
                "accepted \(address) as a pipe's base URL")
        }
    }

    func testShuttingDownTwiceIsFineAndTellsTheFarSide() async throws {
        let pipe = FakePipe(from: .direct)
        let session = try ModelpipeSession(
            pipe: pipe, sleeper: ImmediateSleeper(), grace: .milliseconds(1))

        await session.shutdown()
        await session.shutdown()

        XCTAssertEqual(pipe.shutdownCount, 2, "shutdown must reach the far side every time")
        var seen: [PipeStatus] = []
        for await status in session.status { seen.append(status) }
        XCTAssertEqual(seen, [.closed], "a stream opened after a shutdown must end, not hang")
    }

    /// The readings the binding exposes, now that the seam has a home for
    /// them — and in the app's vocabulary rather than the binding's, because
    /// nothing above this module may name an `Mp` type.
    ///
    /// `stayOpen: true` is load-bearing. Without it the walk is spent
    /// immediately, the driver ends, and the session is closed before the
    /// first assertion — so "a pipe that is open" would be asserted about one
    /// that had already shut.
    func testTheReadingsCrossTheSeamInTheAppsOwnVocabulary() async throws {
        let pipe = FakePipe(from: .direct, baseUrl: "http://127.0.0.1:51234/v1", stayOpen: true)
        let session = try ModelpipeSession(
            pipe: pipe, sleeper: ImmediateSleeper(), grace: .milliseconds(1))

        XCTAssertEqual(session.readings.port, 51234)
        XCTAssertEqual(session.readings.relayConnections, 3)
        XCTAssertEqual(session.readings.relayConnectionsFailed, 1)
        XCTAssertNil(session.closeReason, "a pipe that is open has no reason to have closed")

        await session.shutdown()
        XCTAssertEqual(session.closeReason, .shutdown)

        await session.notifyNetworkChange()
        XCTAssertEqual(pipe.networkChangeCount, 1)
    }

    /// The case the binding cannot report, and the reason this enum has three
    /// cases where `MpCloseReason` has two.
    ///
    /// A pipe whose peer stops answering ends its status sequence with no
    /// reason recorded. Read straight off the binding that is `nil`, which is
    /// also what an open pipe answers — so the session has to know the
    /// sequence ended before it can call the silence anything.
    func testAPeerThatSimplyVanishesIsSaidToHaveVanished() async throws {
        let pipe = FakePipe(from: .direct, reason: nil)
        let session = try ModelpipeSession(
            pipe: pipe, sleeper: ImmediateSleeper(), grace: .milliseconds(1))

        var seen: [PipeStatus] = []
        for await status in session.status { seen.append(status) }

        XCTAssertEqual(seen.last, .closed)
        XCTAssertEqual(
            session.closeReason, .peerVanished,
            "a close the binding recorded no reason for is a peer that went away, not an open pipe")
    }

    /// The other reason worth a sentence, and the one that names this device
    /// rather than the far machine.
    func testAListenerFailureIsBlamedOnThisDeviceAndNotTheNetwork() async throws {
        let pipe = FakePipe(from: .direct, reason: .listenerFailed)
        let session = try ModelpipeSession(
            pipe: pipe, sleeper: ImmediateSleeper(), grace: .milliseconds(1))

        for await _ in session.status {}

        XCTAssertEqual(session.closeReason, .listenerFailed)
        XCTAssertEqual(
            session.closeReason?.sentence(naming: "Home"),
            "This device stopped accepting the connection to Home.")
    }
}
