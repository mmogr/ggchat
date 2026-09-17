import GGChatCore
import XCTest

@testable import GGChatPipe

/// `ModelpipePairingReader` against `docs/pairing-v0.md`'s normative vectors,
/// through the real binding.
///
/// The vectors are hard-coded rather than generated. modelpipe's
/// `pairing_vectors.py` has no `--update` flag on purpose — *"a v0 vector
/// that changes is a broken client in another language, not a stale
/// fixture"* — so what is written here is what all three implementations
/// have to agree on.
final class PairingReaderTests: XCTestCase {
    private let reader = ModelpipePairingReader()

    /// Vector 1: a ticket alone.
    private static let ticket1 = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    /// Vector 3's ticket, which carries addresses.
    private static let ticket3 =
        "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaicaajcaainxaaaaaaaaaaaaaaaaaaach4qaabstehw"
    /// Vector 4 is printed upper case, as a QR code carries it; this is the
    /// ticket it reads as.
    private static let ticket4 =
        "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaqaaangq5duobztulzpojswyylzfzsxqylnobwgkltd"
        + "n5ws6aiaa3akqaihcfiqbrp5xr4q"

    private func read(_ input: String, _ file: StaticString = #filePath, _ line: UInt = #line) -> ReadPairing? {
        switch reader.read(input) {
        case .success(let read): return read
        case .failure(let error):
            XCTFail("refused: \(error.errorDescription ?? "no sentence")", file: file, line: line)
            return nil
        }
    }

    private func refusal(_ input: String, _ file: StaticString = #filePath, _ line: UInt = #line) -> String? {
        switch reader.read(input) {
        case .success(let read):
            XCTFail("accepted, as \(read.ticket) hasCode=\(read.hasCode)", file: file, line: line)
            return nil
        case .failure(let error):
            guard case .malformed(let message) = error else { return nil }
            return message
        }
    }

    // MARK: - The five accepted vectors

    /// Vectors 1, 2, 3 and 5: each reads as the ticket the spec gives, in
    /// canonical lower case, and says whether a code is there without ever
    /// handing the digits back.
    func testTheAcceptedVectorsReadAsTheSpecSays() {
        let code = "483920"
        XCTAssertEqual(read(Self.ticket1), ReadPairing(ticket: Self.ticket1, hasCode: false))
        XCTAssertEqual(read("\(Self.ticket1)-\(code)"), ReadPairing(ticket: Self.ticket1, hasCode: true))
        // Vector 3: addresses in the ticket, and a code with leading zeros,
        // which is a code and not the number 417.
        XCTAssertEqual(read("\(Self.ticket3)-000417"), ReadPairing(ticket: Self.ticket3, hasCode: true))
        // Vector 5: ASCII whitespace at either end, which is how a string
        // copied out of a terminal or a message arrives.
        XCTAssertEqual(read(" \t\(Self.ticket1)-\(code)\r\n"), ReadPairing(ticket: Self.ticket1, hasCode: true))
    }

    /// Vector 4: the whole string upper-cased, which is what a QR code
    /// carries — QR alphanumeric mode encodes upper case and base32 tickets
    /// are printed lower. It has to read as the same ticket the lower-case
    /// form does, or the scanner and the paste would store two different
    /// digests for one machine.
    func testAQRScanReadsTheSameTicketAsThePaste() {
        let scanned =
            "PIPEADLVVGABQKYQVN6VJP7NHSLEA45A5YLS6PNKMIZFV4BBU2HXA5IRUAQAAANGQ5DUOBZTULZPOJSWYYLZ"
            + "FZSXQYLNOBWGKLTDN5WS6AIAA3AKQAIHCFIQBRP5XR4Q-017284"
        XCTAssertEqual(read(scanned), ReadPairing(ticket: Self.ticket4, hasCode: true))
        XCTAssertEqual(read(Self.ticket4), ReadPairing(ticket: Self.ticket4, hasCode: false))
        XCTAssertEqual(read(Self.ticket1.uppercased())?.ticket, Self.ticket1)
    }

    /// The answer the form switches its token field on: a bare ticket has no
    /// code to redeem for a token, so one is asked for.
    func testABareTicketCarriesNoCode() {
        XCTAssertEqual(read(Self.ticket1)?.hasCode, false)
        XCTAssertEqual(read(" \(Self.ticket1) ")?.hasCode, false)
        XCTAssertEqual(read("\(Self.ticket1)-000000")?.hasCode, true)
    }

    // MARK: - Refusals

    /// Four rows of the spec's refusal table, each arriving as a sentence
    /// that could be shown under the field. The sentence is modelpipe's; the
    /// assertions are about what it must not carry — the paste, which may
    /// hold a one-time code, and the binding's own type names, which is what
    /// uniffi's `localizedDescription` would have rendered.
    ///
    /// The first case is the one `ScreenGalleryUITests.testTheProviderFormExplainsABadTicket`
    /// waits for on screen, quoted here off a real call so the walk's
    /// expectation has a source in this repository.
    func testARefusalIsModelpipesOwnSentenceAndNotThePaste() {
        XCTAssertEqual(
            refusal("nope"),
            "That pairing string could not be read (the part before the code is not a ticket).")

        let pastes = [
            // a separator with nothing after it
            "\(Self.ticket1)-",
            // a code one digit short
            "\(Self.ticket1)-48392",
            // a code with a letter in it
            "\(Self.ticket1)-48392a",
            // nothing but whitespace
            " \t\r\n",
        ]
        for paste in pastes {
            guard let message = refusal(paste) else { continue }
            XCTAssertTrue(message.hasSuffix("."), message)
            XCTAssertFalse(message.contains(paste), "the sentence repeats the paste: \(message)")
            XCTAssertFalse(message.contains("MpPairError"), message)
            XCTAssertFalse(message.contains("Modelpipe."), message)
        }
    }

    /// The reader decodes rather than glancing at the shape, which is the
    /// thing the check this replaced could not do: `…p2nb` is `…p2na` with
    /// its last character moved on, so it has the prefix, the alphabet and
    /// the length of a ticket and fails only on its checksum.
    func testATicketWithABadChecksumIsRefusedAsItIsTyped() {
        let flipped = String(Self.ticket1.dropLast()) + "b"
        XCTAssertEqual(flipped.count, Self.ticket1.count)
        XCTAssertNotNil(refusal(flipped))
    }

    /// modelpipe trims ASCII whitespace and nothing else, and its refusal
    /// table lists a non-ASCII space after the code as a refusal. The parser
    /// this replaced trimmed `.whitespacesAndNewlines`, so it accepted both
    /// of these and the pairing then refused them — the form said "a ticket
    /// and a code" about a string that could never be paired with.
    func testUnicodeWhitespaceIsNotTrimmed() {
        XCTAssertNotNil(refusal("\(Self.ticket1)-483920\u{00a0}"))
        XCTAssertNotNil(refusal("\u{00a0}\(Self.ticket1)"))
    }
}
