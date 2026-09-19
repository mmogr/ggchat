import Foundation

/// What a pairing string turned out to be: who it names, and whether it
/// carries a code.
///
/// Not the code's digits. Nothing above the seam needs them — the whole
/// string goes to ``PipeConnector/pair(pairing:deviceName:)``, which spends
/// the code itself — so a type that carried them would be one more place a
/// one-time secret could be logged, shown or held in a view's state.
public struct ReadPairing: Sendable, Equatable {
    /// The ticket, in modelpipe's canonical lower-case form, whatever case
    /// the string was pasted or scanned in. What the Keychain and
    /// ``Ticket/digest(_:)`` are given.
    public let ticket: String
    /// Whether this is a first pairing, with a code to redeem, rather than a
    /// bare ticket for a device that already holds its key. What the form
    /// asks for a token on.
    public let hasCode: Bool

    public init(ticket: String, hasCode: Bool) {
        self.ticket = ticket
        self.hasCode = hasCode
    }
}

/// The ticket never reaches the value's printed form. Interpolated,
/// reflected or dumped, a `ReadPairing` shows the ticket's
/// ``Ticket/digest(_:)`` in its place, the non-secret fingerprint a
/// `ProviderConfig` already keeps, so two readings can still be told apart
/// in a failed test.
extension ReadPairing: CustomStringConvertible, CustomReflectable {
    public var description: String {
        "ReadPairing(ticket: <digest \(Ticket.digest(ticket))>, hasCode: \(hasCode))"
    }

    public var customMirror: Mirror {
        Mirror(
            self, children: ["ticket": "<digest \(Ticket.digest(ticket))>", "hasCode": hasCode],
            displayStyle: .struct)
    }
}

/// Why a pairing string could not be read.
///
/// One case, carrying a sentence written elsewhere. The reasons a pairing
/// string is not one belong to whoever parses it, and an enum here that
/// named them would be a second copy of that list — the copy this app kept
/// until modelpipe exported a reader, and the one that already disagreed
/// with it about whether a non-breaking space is whitespace.
public enum PairingReadError: Error, Sendable, Equatable, LocalizedError {
    /// The string is not a pairing string. The message is the sentence to
    /// show, from whoever refused it, and never contains what was pasted.
    case malformed(message: String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let message): message
        }
    }
}

/// Reads a pairing string, synchronously, without dialling anything.
///
/// The form checks what is typed as it is typed and the scanner accepts or
/// drops each candidate the lens sees, so this cannot be `async`: both are
/// answers a view needs while it is being laid out.
///
/// A protocol in Core rather than a method on ``PipeConnector`` because
/// `MockPipeConnector` lives here too and cannot call the binding, while
/// this has exactly one real implementation and no useful mock — a reader
/// that agreed with itself and not with modelpipe would be the duplication
/// this seam exists to remove. `PipeConnectorFactory` hands out the real one
/// in every build, DEBUG included.
public protocol PairingReader: Sendable {
    func read(_ pairing: String) -> Result<ReadPairing, PairingReadError>
}

/// The pairing field itself, as opposed to what is in it.
///
/// One question only: has anything been typed yet? A form needs that before
/// it needs a read, because an empty field is not a mistake and showing a
/// refusal under one would be answering a question nobody asked. Both forms
/// ask it here rather than each keeping its own rule.
public enum PairingField {
    /// Whether the field is still empty — nothing, or nothing but the
    /// whitespace modelpipe trims.
    ///
    /// modelpipe's own set and no other: space, tab, line feed, form feed
    /// and carriage return, which is what `docs/pairing-v0.md` lists and what
    /// Rust's `char::is_ascii_whitespace` is. Not `.whitespacesAndNewlines`,
    /// which is Unicode whitespace — the set the parser this change deletes
    /// trimmed, and the reason it accepted strings `mpPair` refused. So a
    /// field holding one non-breaking space is something typed, and gets
    /// modelpipe's refusal rather than the guidance for an empty field.
    ///
    /// This decides only whether anything was typed. It never decides what
    /// the text means: the text goes to ``PairingReader`` exactly as typed,
    /// and modelpipe does its own trimming there.
    ///
    /// Asked of the UTF-8 rather than the `Character`s, because Swift reads
    /// a CRLF as one `Character` and that one would match nothing in the
    /// set — a paste ending in `\r\n` would come out as text somebody typed.
    /// Every byte of a non-ASCII scalar is at least 0x80, so none of them
    /// can match either.
    public static func isBlank(_ pairingText: String) -> Bool {
        pairingText.utf8.allSatisfy(asciiWhitespace.contains)
    }

    private static let asciiWhitespace: Set<UInt8> = [0x20, 0x09, 0x0a, 0x0c, 0x0d]
}
