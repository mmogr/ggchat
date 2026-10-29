import Foundation

/// Where the models this device runs are kept: `ggchat-models` under
/// Application Support, readable by this user alone and marked
/// `isExcludedFromBackup`, as `ggchat-store` is. A model is gigabytes that
/// Hugging Face keeps anyway, so no backup should carry it. The mark is set
/// on the directory; which backups then leave the files in it out is Apple's
/// behaviour and is not checked here, as `StoreDirectory` says of its own.
///
/// The app makes and marks the directory and the library writes the files in
/// it: gglib's downloads land here, named by the path this hands it. Made and
/// marked at launch, before each download, and again after each one that
/// finished, so a file the library made or replaced in it is under a marked
/// directory whatever the library did to it.
///
/// The lines that make and mark it repeat `StoreDirectory`'s rather than
/// share them, for the reason that type gives about `PipeIdentityFiles`:
/// what a failure means differs. Here it refuses the download, so no model
/// is written where a backup reaches.
///
/// It also says how much room the volume has for a download, from
/// `volumeAvailableCapacityForImportantUsage`: the figure Apple gives for
/// something the person asked for, which counts space the system would free
/// for it [unverified on a phone].
nonisolated struct ModelsDirectory: Sendable {
    /// The directory's name under Application Support, pinned by a test.
    static let directoryName = "ggchat-models"

    let directory: URL
    /// Reads the room the volume holding a directory has for a download, or
    /// nil where it will not say. Tests stand in a figure.
    var readRoom: @Sendable (URL) -> UInt64? = { ModelsDirectory.importantCapacity(of: $0) }

    /// The app's own place, or nil where the platform will not name
    /// Application Support. Makes nothing (a test checks).
    static func applicationSupport() -> ModelsDirectory? {
        guard
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        return ModelsDirectory(directory: support.appending(path: directoryName, directoryHint: .isDirectory))
    }

    /// Makes the directory, handing `createDirectory` `0o700` for one it
    /// makes (a test checks the mode), and sets the mark every time, on one
    /// that was already there too.
    func prepare() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// The room the volume has for a download, or nil where it will not say.
    func room() -> UInt64? {
        readRoom(directory)
    }

    /// The volume's `volumeAvailableCapacityForImportantUsage`, read afresh:
    /// a URL keeps the values it has read, for `StoreScratch`'s reason.
    static func importantCapacity(of url: URL) -> UInt64? {
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { UInt64(clamping: $0) }
    }
}
