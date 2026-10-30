import Foundation

/// The two folders gglib's model library keeps its files in, which this side
/// makes and names and gglib writes into: its database, `gglib.db`, in
/// ``data``, `ggchat-gglib` under Application Support; and every download in
/// ``models``, the app's `ggchat-models`, whose path the app hands over so
/// the room it checks before a download and the folder gglib writes to are
/// one folder.
///
/// What stays on this side is what `PipeIdentityFiles` keeps on its own:
/// making each folder `0o700` as it is created and marking it out of the
/// backup. gglib makes a folder that is missing with neither, so both are
/// made here first, each time the library is opened. The database goes out
/// of the backup with the weights it lists: a phone restored with the rows
/// and none of the files would list models it does not have.
///
/// The lines repeat `PipeIdentityFiles`' rather than share them, for the
/// reason the app's own folders give: what a failure means differs. Here it
/// refuses to open the library, so nothing of it is written where a backup
/// reaches.
public struct LibraryFolders: Sendable, Equatable {
    /// The database folder's name under Application Support, pinned by a
    /// test.
    public static let dataDirectoryName = "ggchat-gglib"

    public let data: URL
    public let models: URL

    public init(data: URL, models: URL) {
        self.data = data
        self.models = models
    }

    /// The app's own: the database under Application Support, the models in
    /// `models`. Nil where the platform will not name Application Support.
    /// Makes nothing; opening the library does.
    public static func applicationSupport(models: URL) -> LibraryFolders? {
        guard
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        return LibraryFolders(
            data: support.appending(path: dataDirectoryName, directoryHint: .isDirectory), models: models)
    }

    /// Makes both folders, handing `createDirectory` `0o700` for one it
    /// makes, and marks each out of the backup, one already there too.
    func prepare() throws {
        for folder in [data, models] {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var url = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
    }
}
