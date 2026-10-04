import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// Where the conversation store is kept: `ggchat-store` under Application
/// Support, private to this user and marked out of the backup, or — when it
/// cannot be kept there — nowhere, with a notice saying so.
///
/// These are the package's first tests to open a store on disk. Each that
/// opens one does it in a scratch directory of its own (`StoreScratch`). The
/// two that name the app's real places open nothing, and check that neither
/// `ggchat-store` nor any of the store's three files appears there.
final class StoreDirectoryTests: XCTestCase {
    private let scratch = StoreScratch()

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    /// Opened, the store is inside its directory, with CloudKit set to
    /// `.none`: all three of SQLite's files while the store is open, and
    /// nothing named after it left beside the directory. The directory is
    /// readable by this user alone and marked out of the backup.
    @MainActor
    func testTheStoreOpensInsideADirectoryNoBackupCarries() throws {
        let location = scratch.location

        let opened = SwiftDataStore.open(at: location, log: NoopLogSink())
        let store = SwiftDataStore(container: opened.container)
        try store.save(conversation: StoreScratch.conversations(1, providerID: UUID())[0])

        let configuration = try XCTUnwrap(opened.container.configurations.first)
        XCTAssertEqual(configuration.url, location.storeURL)
        // `CloudKitDatabase` has no public equality, so its description is
        // compared with that of `.none`, which differs from `.automatic`'s.
        let none = String(describing: ModelConfiguration.CloudKitDatabase.none)
        XCTAssertNotEqual(String(describing: ModelConfiguration.CloudKitDatabase.automatic), none)
        XCTAssertEqual(String(describing: configuration.cloudKitDatabase), none)
        XCTAssertEqual(
            try scratch.isExcludedFromBackup(location.directory), true,
            "every conversation would ride the next backup")
        let mode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: location.directory.path(percentEncoded: false))[
                .posixPermissions] as? NSNumber)
        XCTAssertEqual(
            mode.int16Value & 0o077, 0, "another user can read the store: \(String(mode.int16Value, radix: 8))")
        // `.ggchat_SUPPORT` is where SwiftData writes an image's bytes, made
        // with the store because a row keeps some outside it: inside the
        // directory, so the mark covers it too.
        XCTAssertEqual(
            scratch.names(in: location.directory),
            [".ggchat_SUPPORT", "ggchat.store", "ggchat.store-shm", "ggchat.store-wal"])
        XCTAssertEqual(
            scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }, [],
            "part of the store was made at the old place, where a backup carries it")
        withExtendedLifetime(store) {}
    }

    /// With a regular file standing where the directory belongs, nothing is
    /// kept: the container is in memory, no store file appears at the old
    /// place, and the notice says so. The log names no path.
    @MainActor
    func testWithNowhereToKeepTheStoreNothingIsKeptAndTheNoticeSaysSo() throws {
        let location = scratch.location
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: location.directory.path(percentEncoded: false), contents: Data("not a directory".utf8))
        let log = CapturingLogSink()

        let opened = SwiftDataStore.open(at: location, log: log)

        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
        XCTAssertEqual(
            scratch.names(in: scratch.support), ["ggchat-store"], "a store was opened where a backup reaches")
        XCTAssertEqual(opened.notice, StoreNotice(keptInMemory: true, olderStoreLeftBehind: false))
        XCTAssertFalse(log.lines.isEmpty, "the fall-back to memory went unlogged")
        for line in log.lines {
            XCTAssertFalse(line.contains(scratch.root.path(percentEncoded: false)), "a log line names a path: \(line)")
        }
    }

    /// A directory that is already there without the mark is marked when the
    /// store opens: the launch that made the directory is not the only one
    /// that sets the mark.
    @MainActor
    func testADirectoryMadeWithoutTheMarkIsMarkedWhenTheStoreOpens() throws {
        let location = scratch.location
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        XCTAssertNotEqual(try scratch.isExcludedFromBackup(location.directory), true, "the directory began marked")

        let opened = SwiftDataStore.open(at: location, log: NoopLogSink())

        XCTAssertNil(opened.notice)
        XCTAssertEqual(try scratch.isExcludedFromBackup(location.directory), true)
    }

    /// The directory is `ggchat-store` and the file inside it `ggchat.store`:
    /// a store already in the directory is found by these two names and no
    /// other.
    @MainActor
    func testTheStoresDirectoryAndFileNamesDoNotMove() {
        XCTAssertEqual(StoreDirectory.directoryName, "ggchat-store")
        XCTAssertEqual(StoreDirectory.fileName, "ggchat.store")
    }

    /// The constructor the app uses puts the store at
    /// `<Application Support>/ggchat-store/ggchat.store` and asks SwiftData
    /// for the old place. Every other test names its own places, so without
    /// this one a default at the wrong place would pass them all. It makes
    /// none of the four names in `placesNamed` (looked for before and after).
    @MainActor
    func testTheAppsOwnStoreIsInsideTheDirectoryUnderApplicationSupport() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let before = present(in: support)

        let location = try XCTUnwrap(StoreDirectory.applicationSupport())

        XCTAssertEqual(
            location.storeURL.standardizedFileURL.path(percentEncoded: false),
            support.appending(path: "ggchat-store/ggchat.store").standardizedFileURL.path(percentEncoded: false))
        XCTAssertEqual(location.legacyStore, ModelConfiguration("ggchat", schema: SwiftDataStore.schema).url)
        XCTAssertEqual(present(in: support), before, "naming the app's own places made something there")
    }

    /// Earlier builds opened `ModelConfiguration("ggchat", schema:)` naming
    /// no URL, and the old place is that configuration's `url`. Asked here, it
    /// is `ggchat.store` at the root of Application Support, the file those
    /// builds' DEBUG reset deleted, and asking makes none of the four names in
    /// `placesNamed` (looked for before and after).
    @MainActor
    func testSwiftDataNamesTheOldPlaceWithoutCreatingIt() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let before = present(in: support)

        let url = ModelConfiguration("ggchat", schema: SwiftDataStore.schema).url

        XCTAssertEqual(
            url.standardizedFileURL.path(percentEncoded: false),
            support.appending(path: "ggchat.store").standardizedFileURL.path(percentEncoded: false))
        XCTAssertEqual(present(in: support), before, "asking SwiftData made something there")
    }

    /// The directory and the three files at the old place, by name.
    private let placesNamed = ["ggchat-store", "ggchat.store", "ggchat.store-wal", "ggchat.store-shm"]

    /// Which of `placesNamed` are in `directory`, each looked for by a path
    /// built by hand.
    private func present(in directory: URL) -> [String] {
        placesNamed.filter { scratch.exists(directory.appending(path: $0)) }
    }

    /// A launch with nothing to report shows nothing.
    @MainActor
    func testANormalOpenHasNothingToSay() {
        let opened = SwiftDataStore.open(at: scratch.location, log: NoopLogSink())

        XCTAssertNil(opened.notice)
        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, false)
    }
}
