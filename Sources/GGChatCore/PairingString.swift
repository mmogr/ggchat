import Foundation

/// Why a pairing string is not one. Each case is a sentence the form can
/// show as-is, so a bad paste is explained where it was pasted.
public enum PairingStringError: Error, Sendable, Equatable, LocalizedError {
    /// Nothing was typed, or only whitespace was.
    case empty
    /// There is a `-`, but what follows it is not the six-digit code.
    case suffixIsNotACode
    /// The part before the code is not a ticket. Carries the shape error so
    /// the sentence is the ticket's own, not a second-hand summary of it.
    case badTicket(TicketShapeError)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Paste the “ticket-code” string `gglib remote enable` shows, or a bare ticket "
                + "once this device holds the key."
        case .suffixIsNotACode:
            "The part after the last “-” should be the \(PairingString.codeLength)-digit pairing code."
        case .badTicket(let shape):
            shape.errorDescription
        }
    }
}

/// The one string `gglib remote enable` prints, taken apart: a ticket saying
/// who to dial, and — the first time — a one-time code to redeem for that
/// machine's API key.
///
/// This is the Swift half of gglib's `remote/pairing_string.rs`, and the
/// split rule is its rule: on the **last** `-`. A ticket's alphabet is
/// `pipe` and base32, which has no hyphen, so the only `-` that can appear
/// is the separator `enable` put there. A bare ticket is the later-session
/// form, once the key is already stored.
public struct PairingString: Sendable, Equatable {
    /// The ticket, lowercased. A printed QR encodes the whole string
    /// uppercased, and a paste arrives as printed, so both normalise here
    /// and compare equal downstream.
    public var ticket: String
    /// The six-digit code, when this is a first pairing.
    public var code: String?

    /// How many digits a pairing code has. The other half of gglib's
    /// `gglib_core::access::generate_pairing_code`.
    public static let codeLength = 6

    public init(ticket: String, code: String? = nil) {
        self.ticket = ticket
        self.code = code
    }

    /// The canonical form: what `parse` would accept again unchanged, with
    /// the ticket lowercased. What the scanner hands back to the form.
    public var canonical: String {
        code.map { "\(ticket)-\($0)" } ?? ticket
    }

    /// Parse `ticket` or `ticket-code`, in any ASCII case.
    ///
    /// The ticket is only shape-checked, never decoded — decoding belongs to
    /// the ffi. The code is checked for exactly six ASCII digits, which is
    /// what makes the split unambiguous: a suffix that is not a code is a
    /// mistake worth naming rather than a ticket with a hyphen in it.
    public static func parse(_ input: String) -> Result<PairingString, PairingStringError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        var ticketPart = trimmed
        var code: String?
        if let separator = trimmed.lastIndex(of: "-") {
            let suffix = String(trimmed[trimmed.index(after: separator)...])
            guard isCode(suffix) else { return .failure(.suffixIsNotACode) }
            ticketPart = String(trimmed[..<separator])
            code = suffix
        }
        let ticket = Ticket.normalized(ticketPart)
        if case .failure(let shape) = Ticket.validateShape(ticket) { return .failure(.badTicket(shape)) }
        return .success(PairingString(ticket: ticket, code: code))
    }

    /// Six ASCII digits and nothing else. Checked over UTF-8 rather than
    /// characters so that a full-width or Arabic-Indic digit is not counted
    /// as one: the far machine compares bytes.
    private static func isCode(_ suffix: String) -> Bool {
        let bytes = Array(suffix.utf8)
        return bytes.count == codeLength && bytes.allSatisfy { (0x30...0x39).contains($0) }
    }
}
