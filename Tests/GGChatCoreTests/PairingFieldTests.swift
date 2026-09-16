import XCTest

@testable import GGChatCore

/// The one question the forms ask before they ask modelpipe anything.
final class PairingFieldTests: XCTestCase {
    /// `docs/pairing-v0.md`'s `string_form.trimmed`, and nothing else. The
    /// non-breaking space is the case that matters: `.whitespacesAndNewlines`
    /// would call it whitespace, modelpipe does not, and a field holding one
    /// has to reach the reader and be refused rather than pass for an empty
    /// field with guidance under it.
    func testOnlyModelpipesOwnWhitespaceCountsAsNothingTyped() {
        XCTAssertTrue(PairingField.isBlank(""))
        XCTAssertTrue(PairingField.isBlank(" \t\r\n"))
        XCTAssertTrue(PairingField.isBlank("\u{0c}"), "form feed is in modelpipe's set")
        // Swift reads CRLF as one Character, so a rule written over
        // Characters would call a pasted line ending something somebody
        // typed. This one is written over UTF-8.
        XCTAssertTrue(PairingField.isBlank("\r\n"))

        XCTAssertFalse(PairingField.isBlank("\u{00a0}"), "a non-breaking space is something typed")
        XCTAssertFalse(PairingField.isBlank("\u{2003}"), "an em space is something typed")
        XCTAssertFalse(PairingField.isBlank("\u{0b}"), "a vertical tab is not in modelpipe's set")
        XCTAssertFalse(PairingField.isBlank("x"))
        XCTAssertFalse(PairingField.isBlank(" x "))
    }
}
