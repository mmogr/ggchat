import Foundation

/// Where this device keeps the endpoint keys it dials machines with.
///
/// Without one, modelpipe mints a key per process, so this device is a
/// different device to the far machine after every launch: the fingerprint
/// recorded beside its key as the code was redeemed names a peer that no
/// longer exists, so a serving machine that shows where a device paired from
/// — gglib does, on `main` after v0.18.0 — is showing something that cannot
/// be compared with anything. With one, that fingerprint is this device for
/// as long as the file lives.
///
/// **One file per far machine**, and from modelpipe-ffi 0.4.0 the binding is
/// what names it: it is handed this directory and writes
/// `<the ticket's digest>.key` inside it. A single file for the whole app
/// would be smaller, and wrong: a key is an endpoint, and iroh's relay allows
/// one live connection per endpoint id — a second dial with the same key
/// deactivates the first machine's relay path for as long as the second is
/// up, though a direct path is untouched. This app holds a session per pipe
/// provider and dials them all on a resume, so two machines have to be two
/// endpoints. Keying on the far machine also means a phone that pairs with
/// two desktops presents each of them a different fingerprint, and neither
/// can tell it is the same phone.
///
/// The name is the digest of the canonical ticket, and this app no longer
/// computes it for the file — the binding does, from the ticket it parsed.
/// It has to land where this app used to put it, or an already-paired device
/// stops finding its key, so that is a claim worth a test rather than a
/// comment; `BindingTests` pins the literal from both ends.
///
/// What stays on this side is the part Rust cannot do portably: making the
/// directory `0o700` at the moment it is created, and marking it out of the
/// backup. modelpipe creates no directory — a directory that is named but
/// absent surfaces as `MpError.Identity`.
///
/// Not a credential, whatever it looks like. It admits nothing: the far edge
/// admits the bearer key, which lives in the Keychain like every other
/// secret this app holds. This is a name, and it is a file rather than a
/// Keychain item because the binding takes a directory and writes the files
/// itself. `docs/adr/0004-the-connect-identity-is-a-file.md` is the whole
/// argument.
///
/// Every failure here answers `nil`, which dials with no identity — what
/// every build before this one did. A phone that cannot write to its own
/// container should lose a stable fingerprint, not the ability to connect.
struct PipeIdentityFiles: Sendable {
    /// The directory the files live in. Its contents are modelpipe's
    /// business; this type only ever makes the directory and names it.
    let directory: URL

    /// The app's own place for these, or `nil` where the platform will not
    /// name one.
    ///
    /// Application Support rather than Documents or Caches: not shown to the
    /// person, not offered to the Files app, and not a directory the system
    /// may empty under the app — a purged identity would silently change
    /// this device's fingerprint on every machine it has paired with.
    static func applicationSupport() -> PipeIdentityFiles? {
        guard
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: true)
        else { return nil }
        return PipeIdentityFiles(directory: support.appending(path: "pipe-identities"))
    }

    /// The directory to hand the binding, or `nil` if this device cannot keep
    /// one.
    ///
    /// Made before it is named, because modelpipe will not create it: the
    /// binding is handed a directory it expects to exist, and one that does
    /// not surfaces as a refusal naming the key file rather than as a dial
    /// with no identity. Answering `nil` is how this side says "no identity"
    /// deliberately.
    func directoryPath() -> String? {
        guard ensureDirectory() else { return nil }
        return directory.path(percentEncoded: false)
    }

    /// Make the directory, private and out of the backup, and say whether
    /// there is now one to write into.
    ///
    /// The mode rides on the creation rather than being set afterwards, so
    /// there is no moment at which the directory exists and is readable: this
    /// only ever creates the directory the app's own container already
    /// protects, and a chmod of one somebody else made is not this type's
    /// business. `createDirectory` applies attributes to what it creates, so
    /// a directory that is already there keeps whatever it had.
    ///
    /// Out of the backup because a restored phone is a different device and
    /// should look like one. A restore that carried these files would give
    /// two phones one name on the far machine, which is the one thing an
    /// endpoint key may not do; the Keychain items go the other way on
    /// purpose, so the restored phone still holds the keys that admit it and
    /// simply introduces itself afresh. A directory this app cannot mark is
    /// therefore one it will not keep a key in — the dial goes out with no
    /// identity instead, which is what every build before this one did.
    ///
    /// Of the two ways out of here, only the first is covered by a test. A
    /// directory that cannot be made is pinned by
    /// `testWithNowhereToKeepAKeyThereIsNoDirectory`, which stands a file
    /// where the directory belongs. The second is not: `setResourceValues`
    /// does not fail on a directory this process has just created, so
    /// reaching it would mean standing a fake in for `FileManager`, and a
    /// mutation that puts the old `try?` back survives the whole suite. It is
    /// written this way regardless, because the alternative is keeping a key
    /// somewhere a backup could carry it, which is the one thing an endpoint
    /// key may not allow.
    private func ensureDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }
}
