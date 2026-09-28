import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// When the store cannot be kept in `ggchat-store`, nothing is kept: the
/// container is in memory, the notice says so, and what is on disk keeps its
/// bytes. A file at the old place that cannot be marked is logged instead. A
/// mark is refused here by making the file or directory immutable, which
/// `StoreScratch.remove()` undoes.
final class StoreFallbackTests: XCTestCase {
    private let scratch = StoreScratch()

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    /// With no Application Support to name, the container is in memory and
    /// the notice says so.
    @MainActor
    func testWithNoApplicationSupportNothingIsKeptAndTheNoticeSaysSo() {
        let log = CapturingLogSink()

        let opened = SwiftDataStore.open(at: nil, log: log)

        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
        XCTAssertEqual(opened.notice, StoreNotice(keptInMemory: true, olderStoreLeftBehind: false))
        XCTAssertFalse(log.lines.isEmpty, "the fall-back to memory went unlogged")
    }

    /// A directory holding a store that cannot be marked is not used: the
    /// container is in memory, the notice says so, and the store's files
    /// keep their bytes. The log names no path.
    @MainActor
    func testADirectoryThatCannotBeMarkedIsNotUsed() throws {
        let location = scratch.location
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try Data("a store".utf8).write(to: location.storeURL)
        try Data("its log".utf8).write(to: location.directory.appending(path: "ggchat.store-wal"))
        XCTAssertNotEqual(try scratch.isExcludedFromBackup(location.directory), true, "the directory began marked")
        try scratch.setImmutable(location.directory, true)
        let before = try scratch.contents(of: location.directory)
        let log = CapturingLogSink()

        let opened = SwiftDataStore.open(at: location, log: log)

        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
        XCTAssertEqual(opened.notice, StoreNotice(keptInMemory: true, olderStoreLeftBehind: false))
        XCTAssertEqual(try scratch.contents(of: location.directory), before, "the store was touched")
        XCTAssertNotEqual(try scratch.isExcludedFromBackup(location.directory), true, "the mark was not refused")
        XCTAssertFalse(log.lines.isEmpty, "the fall-back to memory went unlogged")
        for line in log.lines {
            XCTAssertFalse(line.contains(scratch.root.path(percentEncoded: false)), "a log line names a path: \(line)")
        }
    }

    /// A main file in the directory that SwiftData will not open is left as
    /// it is: the container is in memory, the notice says so, and the file
    /// keeps its bytes. The log names no path.
    @MainActor
    func testAStoreThatWillNotOpenKeepsItsBytesAndNothingIsKept() throws {
        let location = scratch.location
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: location.storeURL)
        let log = CapturingLogSink()

        let opened = SwiftDataStore.open(at: location, log: log)

        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
        XCTAssertEqual(opened.notice, StoreNotice(keptInMemory: true, olderStoreLeftBehind: false))
        XCTAssertEqual(try Data(contentsOf: location.storeURL), Data("not a database".utf8))
        XCTAssertFalse(log.lines.isEmpty, "the fall-back to memory went unlogged")
        for line in log.lines {
            XCTAssertFalse(line.contains(scratch.root.path(percentEncoded: false)), "a log line names a path: \(line)")
        }
    }

    /// With a store in the directory that will not open and an older build's
    /// store at the old place, the notice carries both, and neither file
    /// changes.
    @MainActor
    func testAStoreThatWillNotOpenBesideAnOlderOneReportsBoth() throws {
        let location = scratch.location
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: location.storeURL)
        try Data("an older build's store".utf8).write(to: location.legacyStore)

        let opened = SwiftDataStore.open(at: location, log: NoopLogSink())

        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
        XCTAssertEqual(opened.notice, StoreNotice(keptInMemory: true, olderStoreLeftBehind: true))
        XCTAssertEqual(try Data(contentsOf: location.storeURL), Data("not a database".utf8))
        XCTAssertEqual(try Data(contentsOf: location.legacyStore), Data("an older build's store".utf8))
    }

    /// A file at the old place that cannot be marked is logged, with no path,
    /// and left as it is; the launch goes on with the store in the directory.
    @MainActor
    func testAFileAtTheOldPlaceThatCannotBeMarkedIsLoggedWithoutAPath() throws {
        let location = scratch.location
        let leftover = scratch.support.appending(path: "ggchat.store-shm")
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        try Data("left behind".utf8).write(to: leftover)
        try scratch.setImmutable(leftover, true)
        let log = CapturingLogSink()

        let opened = SwiftDataStore.open(at: location, log: log)

        XCTAssertNil(opened.notice)
        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, false)
        XCTAssertEqual(try Data(contentsOf: leftover), Data("left behind".utf8))
        XCTAssertTrue(log.lines.contains { $0.hasPrefix("[error]") }, "the refused mark went unlogged: \(log.lines)")
        for line in log.lines {
            XCTAssertFalse(line.contains(scratch.root.path(percentEncoded: false)), "a log line names a path: \(line)")
        }
    }
}
