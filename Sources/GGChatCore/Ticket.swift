import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

/// The little this app does to a modelpipe ticket on its own: fold its case,
/// and fingerprint it.
///
/// Reading one is modelpipe's, through ``PairingReader``. What used to be
/// here — the `pipe` prefix, the base32 alphabet, the padding, the length
/// bounds — was a shape check written from `docs/ticket-format-v0.md`
/// because nothing in the binding would answer a question about a string
/// synchronously. `mpReadPairing` does, and it decodes rather than glances,
/// so a ticket whose checksum is wrong is now refused where the old check
/// waved it through.
public enum Ticket {
    /// The canonical lowercase form, so a QR scan (uppercase) and a paste
    /// (lowercase) of the same ticket compare equal.
    ///
    /// modelpipe hands its ticket back in this form already. This stays for
    /// ``digest(_:)``, whose input is whatever was stored — including by a
    /// version of this app that stored what was typed — and it is private,
    /// because that is now its only caller and a second canonical form on
    /// offer is a second canonical form somebody will reach for.
    private static func normalized(_ ticket: String) -> String {
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
}
