import Foundation
import GGChatCore
import SQLite3
import SwiftData

@testable import GGChatUI

/// A directory of a test's own, named by a fresh UUID under the temporary
/// directory, with a folder in it standing in for Application Support.
///
/// Every store test that opens or moves a store does it here, never in the
/// real place: `swift test` is not sandboxed on macOS, so the Application
/// Support the app would name there is the developer's own.
struct StoreScratch {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ggchat-store-test-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// Stands in for Application Support: where an earlier build left the
    /// store, and where `ggchat-store` is made. Named like the real one,
    /// space included, so a path under it has to be decoded to be found.
    var support: URL { root.appending(path: "Application Support", directoryHint: .isDirectory) }

    /// The store's directory inside `support`, with the names spelt out, and
    /// `ggchat.store` in `support` standing in for the old place.
    @MainActor var location: StoreDirectory {
        StoreDirectory(
            directory: support.appending(path: "ggchat-store", directoryHint: .isDirectory),
            legacyStore: support.appending(path: "ggchat.store"))
    }

    /// Clears the immutable flag on everything under `root`, then removes it.
    func remove() {
        let paths = FileManager.default.enumerator(atPath: root.path(percentEncoded: false))?.allObjects ?? []
        for case let path as String in paths {
            try? setImmutable(root.appending(path: path), false)
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Sets or clears the flag that makes a file or directory immutable, so
    /// that setting its backup mark fails.
    func setImmutable(_ url: URL, _ immutable: Bool) throws {
        var url = url
        var values = URLResourceValues()
        values.isUserImmutable = immutable
        try url.setResourceValues(values)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// What a directory holds, by name and sorted; empty if it is not there.
    func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).sorted()
    }

    /// Every file a directory holds, by name, with its bytes.
    func contents(of directory: URL) throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for name in names(in: directory) {
            contents[name] = try Data(contentsOf: directory.appending(path: name))
        }
        return contents
    }

    /// Read from the disk each time. A URL keeps the resource values it has
    /// read: read again through the same URL, or a copy of it, the mark
    /// answered false after it had been set on disk (seen on macOS).
    func isExcludedFromBackup(_ url: URL) throws -> Bool? {
        var url = url
        url.removeAllCachedResourceValues()
        return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    }

    /// SQLite answered something other than OK while a log was folded in.
    struct FoldFailed: Error, CustomStringConvertible {
        let step: String
        let code: Int32
        var description: String { "SQLite answered \(code) at \(step)" }
    }

    /// Folds the log of the store at `url` into its main file with SQLite's
    /// own `wal_checkpoint(TRUNCATE)`, then removes its `-wal` and `-shm`, so
    /// the store is its main file alone. Nothing else may have that copy
    /// open. The store is read once first: without that read, the checkpoint
    /// answered OK and folded nothing in when this was written (a connection
    /// opens its log at its first read [unverified]). The caller checks the
    /// main file alone for what it expects to be there.
    func foldLogIntoMainFile(_ url: URL) throws {
        var database: OpaquePointer?
        var step = "open"
        var code = sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READWRITE, nil)
        if code == SQLITE_OK {
            step = "read"
            code = sqlite3_exec(database, "SELECT count(*) FROM sqlite_master", nil, nil, nil)
        }
        if code == SQLITE_OK {
            step = "checkpoint"
            code = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        }
        let closed = sqlite3_close(database)
        guard code == SQLITE_OK else { throw FoldFailed(step: step, code: code) }
        guard closed == SQLITE_OK else { throw FoldFailed(step: "close", code: closed) }
        for suffix in ["-wal", "-shm"] {
            let companion = URL(filePath: url.path(percentEncoded: false) + suffix)
            if exists(companion) {
                try FileManager.default.removeItem(at: companion)
            }
        }
    }

    /// A container on disk at `url`, configured the way the app opens its own
    /// store, whose directory must already exist.
    @MainActor
    func container(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ggchat", schema: SwiftDataStore.schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: SwiftDataStore.schema, configurations: [configuration])
    }

    /// Conversations with a question and an answer each, the kind a person
    /// would be upset to lose.
    static func conversations(_ count: Int, providerID: UUID) -> [Conversation] {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            Conversation(
                providerID: providerID, model: "m",
                messages: [
                    Message(role: .user, content: "question \(index)", createdAt: stamp),
                    Message(role: .assistant, content: "answer \(index)", reasoning: "r\(index)", createdAt: stamp),
                ],
                createdAt: stamp, updatedAt: stamp)
        }
    }
}
