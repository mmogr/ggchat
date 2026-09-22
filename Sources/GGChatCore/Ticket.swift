import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    // A fallback here would be a second answer for a value that is written
    // down and compared later. See `Ticket.digest`.
    #error("Ticket.digest needs CryptoKit: see the note on `digest(_:)` about a second rule.")
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

    /// A short, non-secret fingerprint: the first eight bytes of the SHA-256
    /// of the case-folded argument, lowercase hex.
    ///
    /// It folds ASCII case and nothing else — it does not parse a ticket and
    /// does not canonicalise one. Callers hand it whatever they hold: a
    /// ticket modelpipe has already read, or one taken straight back out of
    /// the Keychain.
    ///
    /// It matters because until modelpipe-ffi 0.4.0 this app named this
    /// device's key file for a machine `<digest>.key`, and from 0.4.0 the
    /// binding names it — hashing `Display` of the ticket it parsed. Those
    /// are the same bytes, for two reasons together: the input is the same —
    /// `mpReadPairing` hands back `Display` of the parsed ticket, both call
    /// sites that ever named a key file read through it first, and `Display`
    /// is lowercase ASCII, so the fold above was a no-op on it — and so is
    /// the function, SHA-256 truncated to eight bytes and written as
    /// lowercase hex on both sides. No paired device changes its file name,
    /// for any ticket.
    /// `BindingTests` pins that to a literal — though it cannot see the
    /// difference between the two transforms, because it asks about a ticket
    /// that is already canonical.
    ///
    /// SHA-256 unconditionally. There was a fallback here for a platform
    /// without CryptoKit, FNV-1a in the same sixteen lowercase hex
    /// characters — the same shape and a different value, indistinguishable
    /// by looking at it. A build that took it would write provider records
    /// under a digest nothing else computes, and would quietly stop this
    /// function standing for what 0.3.x named key files by. No platform this
    /// package declares can take that branch, so it was not a fallback but a
    /// second answer waiting for a build to find it.
    public static func digest(_ ticket: String) -> String {
        let hash = SHA256.hash(data: Data(normalized(ticket).utf8))
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
