import GGChatCore
import XCTest

@testable import GGChatUI

/// That the reader the forms and the scanner actually get is modelpipe's,
/// in this build as well as a shipped one.
///
/// These tests compile in DEBUG, which is the whole point: `make()` hands
/// back the mock connector here, and the temptation is to give the reader
/// the same treatment. A mock reader would be a second parse of the pairing
/// format — the one this change deleted — and the screens walked in DEBUG
/// would be walked against it rather than against the rules the shipped app
/// follows.
///
/// Asserted by behaviour rather than by naming `ModelpipePairingReader`,
/// which lives in a module this test target does not depend on. Both of
/// these answers need a real decode of a real ticket, so nothing but the
/// binding can give them.
final class PairingReaderWiringTests: XCTestCase {
    /// modelpipe's normative vector 4 (`docs/pairing-v0.md`), as a QR code
    /// carries it, and the ticket it reads as.
    private let scanned =
        "PIPEADLVVGABQKYQVN6VJP7NHSLEA45A5YLS6PNKMIZFV4BBU2HXA5IRUAQAAANGQ5DUOBZTULZPOJSWYYLZ"
        + "FZSXQYLNOBWGKLTDN5WS6AIAA3AKQAIHCFIQBRP5XR4Q-017284"
    private let readTicket =
        "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaqaaangq5duobztulzpojswyylzfzsxqylnobwgkltd"
        + "n5ws6aiaa3akqaihcfiqbrp5xr4q"

    private func assertIsModelpipes(
        _ reader: any PairingReader, _ file: StaticString = #filePath, _ line: UInt = #line
    ) {
        guard case .success(let read) = reader.read(scanned) else {
            return XCTFail("a QR-cased vector was refused", file: file, line: line)
        }
        XCTAssertEqual(
            read.ticket, readTicket, "the ticket is not in modelpipe's canonical form", file: file, line: line)
        XCTAssertTrue(read.hasCode, file: file, line: line)

        // A ticket the old shape check accepted: right prefix, right
        // alphabet, right length, wrong checksum. Only a decode refuses it.
        let flipped = String(readTicket.dropLast()) + "a"
        guard case .failure = reader.read(flipped) else {
            return XCTFail("a ticket with a bad checksum was accepted", file: file, line: line)
        }
    }

    @MainActor
    func testTheFactoryHandsOutModelpipesReaderInDebugToo() {
        assertIsModelpipes(PipeConnectorFactory.makePairingReader())
        XCTAssertEqual(
            String(describing: type(of: PipeConnectorFactory.makePairingReader())), "ModelpipePairingReader")
    }

    /// And that the app model takes it by default, which is how the views
    /// reach it: they read through `model.pairingReader`.
    @MainActor
    func testTheAppModelTakesThatReaderByDefault() {
        let model = AppModel(store: InMemoryStore(), secrets: InMemorySecrets())
        assertIsModelpipes(model.pairingReader)
    }
}
