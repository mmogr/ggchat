import GGChatCore
import Modelpipe
import Synchronization
import XCTest

@testable import GGChatPipe

/// What the connector does before, during and after a dial, driven by a fake
/// pipe so none of it needs a network.
final class ModelpipeConnectorTests: XCTestCase {
    /// modelpipe's normative vector 1, so a refusal here is about the code
    /// under test and not about the input.
    private let realTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    private func connector(
        sleeper: any Sleeper = ImmediateSleeper(),
        dial: @escaping ModelpipeConnector.Dial
    ) -> ModelpipeConnector {
        ModelpipeConnector(sleeper: sleeper, grace: .milliseconds(1), dial: dial)
    }

    // MARK: - Refused before anything is dialled

    func testATicketOfTheWrongShapeIsRefusedWithoutDialling() async {
        let dialled = Mutex(false)
        let connector = connector { _ in
            dialled.withLock { $0 = true }
            return FakePipe()
        }
        do {
            _ = try await connector.connect(ticket: "nope", token: "a-token")
            XCTFail("a string that is not a ticket was dialled")
        } catch let error as PipeConnectError {
            XCTAssertEqual(error, .invalidTicket(.badPrefix))
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertFalse(
            dialled.withLock { $0 },
            "the shape check has to come first: PipePairing does none of its own")
    }

    func testAnEmptyTokenIsRefusedEvenThoughTheBindingWouldNotWantIt() async {
        let dialled = Mutex(false)
        let connector = connector { _ in
            dialled.withLock { $0 = true }
            return FakePipe()
        }
        do {
            _ = try await connector.connect(ticket: realTicket, token: "   ")
            XCTFail("an empty token was accepted")
        } catch let error as PipeConnectError {
            XCTAssertEqual(error, .missingToken)
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertFalse(dialled.withLock { $0 }, "a pairing dial was spent on an empty code")
    }

    // MARK: - The dial itself

    func testAGoodTicketDialsAndTheTokenGoesNoFurther() async throws {
        let seen = Mutex<String?>(nil)
        let connector = connector { ticket in
            seen.withLock { $0 = ticket }
            return FakePipe(baseUrl: "http://127.0.0.1:49222/v1")
        }
        let session = try await connector.connect(ticket: realTicket, token: "the-key")

        XCTAssertEqual(seen.withLock { $0 }, realTicket)
        XCTAssertEqual(session.baseURL.absoluteString, "http://127.0.0.1:49222/v1")
        // The token is the caller's to put in an Authorization header. The
        // binding takes none, and nothing here may have kept one.
        XCTAssertFalse(
            "\(session)".contains("the-key"), "the session is carrying the token around")
    }

    func testABaseURLThatIsNotAURLFailsTheDialRatherThanCrashing() async {
        let connector = connector { _ in FakePipe(baseUrl: "not a url at all") }
        do {
            _ = try await connector.connect(ticket: realTicket, token: "the-key")
            XCTFail("a base URL that is not one was accepted")
        } catch let error as PipeConnectError {
            guard case .dialFailed(_, let retryable) = error else {
                return XCTFail("expected dialFailed, got \(error)")
            }
            XCTAssertTrue(retryable)
        } catch {
            XCTFail("\(error)")
        }
    }

    // MARK: - Errors from the transport

    /// The one that matters most. `MpError.errorDescription` is
    /// `String(reflecting:)`, so an error allowed through unmapped puts the
    /// inside of the binding on a person's screen.
    func testATransportErrorArrivesAsASentenceAndNotADebugRendering() {
        let refusal = ModelpipeConnector.refusal(
            for: .Bind(reason: "Address already in use (os error 48)"))

        let sentence = refusal.errorDescription ?? ""
        XCTAssertFalse(sentence.isEmpty)
        XCTAssertFalse(
            sentence.contains("MpError"),
            "the debug rendering of the binding's own enum reached the sentence: \(sentence)")
        XCTAssertFalse(sentence.contains("modelpipe_ffi"), sentence)
    }

    /// A bad ticket is the one failure a person can fix by looking at what
    /// they pasted, so offering them a retry would be a lie.
    func testABadTicketIsNotWorthDiallingAgain() {
        XCTAssertFalse(
            ModelpipeConnector.refusal(for: .BadTicket(reason: "bad checksum")).isRetryable)
        XCTAssertFalse(
            ModelpipeConnector.refusal(for: .UnsupportedTicketVersion(version: 9)).isRetryable)
    }

    /// A machine that was asleep may answer next time, and the binding is the
    /// thing that knows which failures are like that.
    func testTheBindingDecidesWhatIsWorthRepeating() {
        let unreachable = ModelpipeConnector.refusal(for: .PeerUnreachable)
        XCTAssertEqual(
            unreachable.isRetryable, MpError.PeerUnreachable.isRetryable(),
            "retryability was decided here instead of being carried from the binding")
    }

    func testAnErrorFromTheDialIsNotSwallowed() async {
        let connector = connector { _ in throw MpError.PeerUnreachable }
        do {
            _ = try await connector.connect(ticket: realTicket, token: "the-key")
            XCTFail("a failed dial produced a session")
        } catch let error as PipeConnectError {
            guard case .dialFailed = error else {
                return XCTFail("expected dialFailed, got \(error)")
            }
        } catch {
            XCTFail("an MpError escaped the connector: \(error)")
        }
    }
}
