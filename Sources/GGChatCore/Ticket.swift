import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

/// Why a ticket string is not the right shape. Each case is a sentence the UI
/// can show as-is.
public enum TicketShapeError: Error, Sendable, Equatable, LocalizedError {
    case empty
    case nonASCII
    case badPrefix
    case badCharacter(offset: Int)
    case padding
    case tooLong(count: Int)
    case badLength(count: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "The ticket is empty."
        case .nonASCII:
            "The ticket contains characters outside ASCII; a real ticket never does."
        case .badPrefix:
            "A ticket starts with “pipe”."
        case .badCharacter(let offset):
            "Character \(offset + 1) is not in the ticket alphabet (a–z, 2–7)."
        case .padding:
            "Tickets carry no “=” padding."
        case .tooLong(let count):
            "The ticket is \(count) characters; the longest possible is \(Ticket.maximumLength)."
        case .badLength(let count):
            "A ticket of \(count) characters cannot be complete; a few characters are missing."
        }
    }
}

/// Shape validation for a modelpipe ticket, from `docs/ticket-format-v0.md`:
/// the ASCII string `pipe` followed by RFC 4648 base32 with no padding.
/// Producers emit lowercase; any ASCII case is accepted. Decoding stays in
/// the ffi; this checks only that a string could be a ticket.
public enum Ticket {
    public static let prefix = "pipe"
    /// The decoded payload is capped at 1024 bytes, so the body is at most
    /// ceil(1024 * 8 / 5) = 1639 characters and the whole string 1643.
    public static let maximumBodyLength = 1639
    public static let maximumLength = prefix.count + maximumBodyLength
    /// modelpipe's minimal v0 ticket decodes to 39 bytes — version 1,
    /// endpoint id 32, address count 1, backend 1, CRC 4 — which is
    /// ceil(39 * 8 / 5) = 63 base32 characters, so 67 with the prefix.
    /// Nothing shorter can be carrying an endpoint id, whatever its
    /// remainder says: `pipeab` used to pass this function.
    public static let minimumBodyLength = 63
    public static let minimumLength = prefix.count + minimumBodyLength

    /// Body lengths that a padding-free base32 encoding can produce.
    private static let validRemainders: Set<Int> = [0, 2, 4, 5, 7]

    public static func validateShape(_ ticket: String) -> Result<Void, TicketShapeError> {
        let bytes = Array(ticket.utf8)
        guard !bytes.isEmpty else { return .failure(.empty) }
        guard bytes.allSatisfy({ $0 < 0x80 }) else { return .failure(.nonASCII) }
        let prefixBytes = Array(prefix.utf8)
        guard bytes.count >= prefixBytes.count,
            zip(bytes, prefixBytes).allSatisfy({ lowercased($0) == $1 })
        else { return .failure(.badPrefix) }
        let body = bytes[prefixBytes.count...]
        guard !body.isEmpty else { return .failure(.badLength(count: bytes.count)) }
        if body.contains(UInt8(ascii: "=")) { return .failure(.padding) }
        guard bytes.count <= maximumLength else { return .failure(.tooLong(count: bytes.count)) }
        for (offset, byte) in body.enumerated() where !isBase32(byte) {
            return .failure(.badCharacter(offset: prefixBytes.count + offset))
        }
        // After the alphabet check, not before it: a short string with a
        // character that is not base32 in it is better described by which
        // character than by how many.
        guard bytes.count >= minimumLength else {
            return .failure(.badLength(count: bytes.count))
        }
        guard validRemainders.contains(body.count % 8) else {
            return .failure(.badLength(count: bytes.count))
        }
        return .success(())
    }

    /// The canonical lowercase form, so a QR scan (uppercase) and a paste
    /// (lowercase) of the same ticket compare equal.
    public static func normalized(_ ticket: String) -> String {
        String(
            ticket.unicodeScalars.map { scalar -> Character in
                guard scalar.isASCII else { return Character(scalar) }
                return Character(String(scalar).lowercased())
            })
    }

    /// A short, non-secret fingerprint used to count distinct tickets the app
    /// has connected to (the kill-criterion reading). Never logged with the
    /// ticket itself.
    public static func digest(_ ticket: String) -> String {
        let data = Data(normalized(ticket).utf8)
        #if canImport(CryptoKit)
            let hash = SHA256.hash(data: data)
            return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        #else
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            return String(format: "%016llx", hash)
        #endif
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private static func isBase32(_ byte: UInt8) -> Bool {
        let lower = lowercased(byte)
        return (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(lower)
            || (UInt8(ascii: "2")...UInt8(ascii: "7")).contains(lower)
    }
}
