import Foundation
import Synchronization
import XCTest

@testable import GGChatCore

/// The step before the seam: `PipePairing` dials the ticket, redeems the code
/// through the pipe that dial opened, and hangs up. The exchange itself — what
/// goes over the wire to gglib's pairing route — is `PairingTests`.
final class PipePairingTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// The pairing step is built out of `PipeConnector` rather than added to
    /// it: dial with the ticket, redeem through the port that dial bound,
    /// hang up, and hand back a token the seam's own two parameters carry.
    func testPairingDialsRedeemsThroughThatPipeAndHangsUp() async throws {
        let connector = SpyPipeConnector()
        let far = RecordingRedeemer(.success("far-machine-key"))
        let key = try await PipePairing(connector: connector, redeemer: far)
            .token(ticket: ticket, code: "483920")

        XCTAssertEqual(key, "far-machine-key")
        XCTAssertEqual(connector.dialled, [ticket], "the ticket alone is what is dialled")
        XCTAssertEqual(far.calls.count, 1)
        let call = try XCTUnwrap(far.calls.first)
        XCTAssertEqual(call.code, "483920")
        XCTAssertEqual(
            call.baseURL, SpyPipeConnector.baseURL,
            "the code goes through the pipe it just opened, not over the open internet")
        XCTAssertEqual(connector.sessions.map(\.shutdowns), [1], "the pairing pipe is hung up")
    }

    /// A spent code must not leave a pipe up. There is nothing to retry
    /// through it: the next attempt starts on the other machine.
    func testTheSessionIsHungUpEvenWhenTheCodeIsRefused() async throws {
        let connector = SpyPipeConnector()
        let pairing = PipePairing(connector: connector, redeemer: RecordingRedeemer(.failure(.refused)))
        do {
            _ = try await pairing.token(ticket: ticket, code: "000000")
            XCTFail("a refused code produced a token")
        } catch let error as PairingError {
            XCTAssertEqual(error, .refused)
        }
        XCTAssertEqual(connector.sessions.map(\.shutdowns), [1], "the pairing pipe is hung up anyway")
    }

    /// The defect this waiting exists for, and it cost a real pairing on a
    /// real phone before it was found.
    ///
    /// `connect` returns as soon as the local port is bound, not once the far
    /// machine answers -- modelpipe's contract, and the seam says so. A redeem
    /// sent into that gap is answered `502` by the tunnel's own edge, because
    /// there is no peer to forward it to, and the one-time code is spent on
    /// that 502. The next attempt needs a fresh `gglib remote enable`.
    ///
    /// Not a rare race. A hole punch through carrier-grade NAT took about two
    /// seconds to reach its first path when this was measured, and the redeem
    /// goes out in microseconds, so on a phone the gap is lost nearly every
    /// time. On a fast LAN it is won often enough that the failure reads as a
    /// code that was simply wrong.
    func testAPipeThatNeverReachesTheFarMachineDoesNotSpendTheCode() async {
        let connector = SpyPipeConnector(reaches: false)
        let far = RecordingRedeemer(.success("never-asked-for"))
        let pairing = PipePairing(
            connector: connector, redeemer: far, sleeper: ImmediateSleeper(),
            patience: .seconds(30))

        do {
            _ = try await pairing.token(ticket: ticket, code: "483920")
            XCTFail("the code was redeemed into a pipe that had reached nobody")
        } catch let error as PairingError {
            guard case .unreachable = error else {
                return XCTFail("expected unreachable, got \(error)")
            }
        } catch {
            XCTFail("\(error)")
        }

        XCTAssertEqual(
            far.calls.count, 0,
            "the redeem went out anyway, which is what spends the code for nothing")
        XCTAssertEqual(
            connector.sessions.map(\.shutdowns), [1],
            "a pairing that gave up still has to hang the pipe up")
    }
}

/// Records what it was asked to dial and hands back a session that counts.
final class SpyPipeConnector: PipeConnector, Sendable {
    static let baseURL = URL(string: "http://127.0.0.1:52001/v1")!

    private let state = Mutex<(tickets: [String], sessions: [SpyPipeSession])>(([], []))

    var dialled: [String] {
        state.withLock { $0.tickets }
    }

    var sessions: [SpyPipeSession] {
        state.withLock { $0.sessions }
    }

    /// Whether the sessions this hands back ever reach the far machine.
    let reaches: Bool

    init(reaches: Bool = true) {
        self.reaches = reaches
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        let session = SpyPipeSession(baseURL: Self.baseURL, reached: reaches)
        state.withLock {
            $0.tickets.append(ticket)
            $0.sessions.append(session)
        }
        return session
    }
}

/// A redeemer with a fixed answer that remembers what it was asked.
final class RecordingRedeemer: PairingRedeemer, Sendable {
    struct Call: Sendable {
        var code: String
        var baseURL: URL
    }

    private let recorded = Mutex<[Call]>([])
    private let outcome: Result<String, PairingError>

    init(_ outcome: Result<String, PairingError>) {
        self.outcome = outcome
    }

    var calls: [Call] {
        recorded.withLock { $0 }
    }

    func redeem(code: String, through baseURL: URL) async throws -> String {
        recorded.withLock { $0.append(Call(code: code, baseURL: baseURL)) }
        return try outcome.get()
    }
}
