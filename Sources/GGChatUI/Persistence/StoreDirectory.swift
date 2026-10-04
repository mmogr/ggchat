import Foundation
import GGChatCore
import SwiftData

/// Where the conversation store is kept: `ggchat-store` under Application
/// Support, readable by this user alone and marked `isExcludedFromBackup`.
/// The mark is set on the directory. Which backups then leave the files in it
/// out is Apple's behaviour and is not checked here.
///
/// Builds before this one opened `ModelConfiguration("ggchat", schema:)`
/// without naming a URL, so SwiftData chose where their store went. The old
/// place is asked of SwiftData the same way: that configuration's `url`, with
/// `-wal` and `-shm` added for SQLite's two companions. A test asks, and
/// checks that asking makes neither `ggchat-store` nor any of those three
/// files. On macOS the answer is `ggchat.store` at the root of Application
/// Support; on iOS it is not checked.
///
/// This moves the only copy of the person's conversations, so:
/// - the directory is made and marked before anything moves into it, and
///   marked again when it is already there;
/// - an earlier build's store moves in with whichever of its files it has,
///   the `-wal` and `-shm` first and the main file last, and only while the
///   directory holds no main file. A move cut short leaves the main file at
///   the old place, and the next launch finishes the move;
/// - no rename replaces a file (seen on macOS). Where one of the same name is
///   already in the directory, the move stops and the launch runs from memory;
/// - a store already in the directory is never replaced. An older build's
///   store at the old place beside it is left there, marked, not opened, and
///   reported in the notice.
///
/// Not guarded: a move cut short, then an older build run before this one
/// opens again. That build opens the main file without the log that moved.
/// If it leaves a log at the old place, the next launch stops the move. If it
/// leaves none, the next launch finishes the move and pairs the log with a
/// main file that build has changed, which can lose conversations. Which of
/// the two happens, and what is lost, is not checked with the app.
///
/// The lines that make and mark the directory repeat
/// `PipeIdentityFiles.ensureDirectory` rather than share it: there a failure
/// dials with no identity, here it keeps nothing.
struct StoreDirectory {
    /// Moves one file, or throws. Tests stand in one that fails partway.
    typealias Mover = (_ from: URL, _ to: URL) throws -> Void

    /// The directory's name and the main file's name inside it, both pinned
    /// by a test: a store already in the directory is found by these alone.
    static let directoryName = "ggchat-store"
    static let fileName = "ggchat.store"
    /// The main file, whose presence means a store is there, moves last.
    static let suffixesInMoveOrder = ["-wal", "-shm", ""]

    /// Where the store lives.
    let directory: URL
    /// The main file of the store earlier builds kept. Its companions are
    /// this path with `-wal` and `-shm` added.
    let legacyStore: URL

    /// The URL the store is opened at.
    var storeURL: URL { directory.appending(path: Self.fileName) }

    /// The app's own places, or `nil` where the platform will not name
    /// Application Support. Asks for Application Support with `create: true`,
    /// as the open did before this. It makes neither the directory nor a
    /// store file (a test checks).
    static func applicationSupport() -> StoreDirectory? {
        guard
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        return StoreDirectory(
            directory: support.appending(path: directoryName, directoryHint: .isDirectory),
            legacyStore: ModelConfiguration("ggchat", schema: SwiftDataStore.schema).url)
    }

    /// Make and mark the directory, then move in a store an earlier build left
    /// behind. Answers whether an older build's store was found beside the one
    /// already here. On every way out, what is left at the old place is marked.
    func prepare(mover: Mover, log: any LogSink) throws -> Bool {
        defer { markWhatIsLeftBehind(log: log) }
        try makeDirectory()
        return try moveInAStoreLeftBehind(mover: mover, log: log)
    }

    /// `createDirectory` is handed `0o700` for a directory it makes (a test
    /// checks the mode), and nothing moves in until it returns. The mark is
    /// set every time.
    private func makeDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func moveInAStoreLeftBehind(mover: Mover, log: any LogSink) throws -> Bool {
        guard exists(legacy("")) else { return false }
        guard !exists(stored("")) else {
            log.log(
                .info,
                "an older build's \(legacyStore.lastPathComponent) is at the old place beside the one in "
                    + "\(directory.lastPathComponent); it is left where it is")
            return true
        }
        for suffix in Self.suffixesInMoveOrder where exists(legacy(suffix)) {
            try mover(legacy(suffix), stored(suffix))
        }
        log.log(
            .info, "moved an earlier build's \(legacyStore.lastPathComponent) into \(directory.lastPathComponent)")
        return false
    }

    /// Each of the store's files at the old place is marked out of the
    /// backup; one that cannot be marked is logged. Nothing there is deleted.
    private func markWhatIsLeftBehind(log: any LogSink) {
        for suffix in Self.suffixesInMoveOrder where exists(legacy(suffix)) {
            var url = legacy(suffix)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            do {
                try url.setResourceValues(values)
            } catch {
                log.log(
                    .error,
                    "could not mark \(url.lastPathComponent) at the old place out of the backup "
                        + "(\(Self.describe(error)))")
            }
        }
    }

    #if DEBUG
        /// Removes the store from both places, and the folder beside the
        /// one it is opened at where SwiftData keeps its external storage:
        /// an image's bytes are a file there, not a row in the store. A store
        /// at the old place is never opened by a build that keeps images, so
        /// it has no such folder. The open that asks for it calls it before
        /// the move, so nothing is moved in behind it.
        func reset(log: any LogSink) {
            for suffix in Self.suffixesInMoveOrder {
                try? FileManager.default.removeItem(at: stored(suffix))
                try? FileManager.default.removeItem(at: legacy(suffix))
            }
            try? FileManager.default.removeItem(at: Self.externalStorage(of: stored("")))
            log.log(.info, "store reset on request")
        }

        /// The hidden folder beside a store where SwiftData writes the values
        /// it keeps outside it: `.ggchat_SUPPORT` for `ggchat.store`, its
        /// files under `_EXTERNAL_DATA` (seen on macOS; a test pins the name).
        static func externalStorage(of store: URL) -> URL {
            let name = "." + store.deletingPathExtension().lastPathComponent + "_SUPPORT"
            return store.deletingLastPathComponent().appending(path: name, directoryHint: .isDirectory)
        }
    #endif

    /// A rename that never replaces: `renamex_np` with `RENAME_EXCL` fails
    /// with `EEXIST` where the destination is there (a test sees this on
    /// macOS; on iOS it is not checked). Across two volumes, `man 2 rename`
    /// says it fails with `EXDEV` rather than copy; that was not run.
    nonisolated static func renameWithoutReplacing(_ from: URL, _ to: URL) throws {
        var failure: Int32 = 0
        let renamed = from.withUnsafeFileSystemRepresentation { source in
            to.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else {
                    failure = EINVAL
                    return false
                }
                guard renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 else {
                    failure = errno
                    return false
                }
                return true
            }
        }
        guard renamed else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
    }

    /// An error as a log line may carry it: its domain and code. A Foundation
    /// file error's own description names the path it failed on (seen on
    /// macOS).
    static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private func legacy(_ suffix: String) -> URL {
        URL(filePath: legacyStore.path(percentEncoded: false) + suffix)
    }

    private func stored(_ suffix: String) -> URL {
        directory.appending(path: Self.fileName + suffix)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

/// What the person has to be told about where their conversations are kept.
public struct StoreNotice: Equatable, Sendable {
    /// The container is in memory only (`isStoredInMemoryOnly`).
    public let keptInMemory: Bool
    /// An older build's store was found at the old place beside the one in
    /// the directory, and left there.
    public let olderStoreLeftBehind: Bool

    /// `nil` when there is nothing to say.
    init?(keptInMemory: Bool, olderStoreLeftBehind: Bool) {
        guard keptInMemory || olderStoreLeftBehind else { return nil }
        self.keptInMemory = keptInMemory
        self.olderStoreLeftBehind = olderStoreLeftBehind
    }
}

/// The container, and what opening it has to tell the person.
public struct OpenedStore {
    public let container: ModelContainer
    public let notice: StoreNotice?
}

extension SwiftDataStore {
    /// The store, opened inside `ggchat-store`; or, when it cannot be kept
    /// there, a container in memory and a notice that says so. The old place
    /// is never opened.
    public static func open(log: any LogSink = OSLogSink(category: "store")) -> OpenedStore {
        #if DEBUG
            // `-ggchat-reset YES` starts from nothing, so a UI test sees the
            // first-run screens. No test reads the flag here.
            let resetRequested = UserDefaults.standard.bool(forKey: "ggchat-reset")
        #else
            let resetRequested = false
        #endif
        return open(at: StoreDirectory.applicationSupport(), resetRequested: resetRequested, log: log)
    }

    /// `open(log:)` at places the caller names, which is how the tests open a
    /// store away from the real Application Support: `swift test` is not
    /// sandboxed on macOS, so there it is the developer's own.
    static func open(
        at location: StoreDirectory?, resetRequested: Bool = false,
        mover: StoreDirectory.Mover = StoreDirectory.renameWithoutReplacing, log: any LogSink
    ) -> OpenedStore {
        guard let location else {
            log.log(.error, "Application Support could not be named, so this launch runs from memory")
            return OpenedStore(
                container: inMemoryContainer(), notice: StoreNotice(keptInMemory: true, olderStoreLeftBehind: false))
        }
        #if DEBUG
            if resetRequested {
                location.reset(log: log)
            }
        #endif
        var olderStoreLeftBehind = false
        do {
            olderStoreLeftBehind = try location.prepare(mover: mover, log: log)
            // CloudKit off in so many words. The default, `.automatic`, would
            // sync the store once the app had an iCloud capability (not
            // checked).
            let configuration = ModelConfiguration(
                "ggchat", schema: schema, url: location.storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return OpenedStore(
                container: container,
                notice: StoreNotice(keptInMemory: false, olderStoreLeftBehind: olderStoreLeftBehind))
        } catch {
            log.log(
                .error,
                "could not keep the store in \(location.directory.lastPathComponent), so this launch runs from "
                    + "memory (\(StoreDirectory.describe(error)))")
            return OpenedStore(
                container: inMemoryContainer(),
                notice: StoreNotice(keptInMemory: true, olderStoreLeftBehind: olderStoreLeftBehind))
        }
    }
}
