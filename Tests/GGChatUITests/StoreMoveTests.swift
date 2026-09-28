import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The move of a store an earlier build left at the old place into
/// `ggchat-store`. These files are the only copy of a person's conversations,
/// so what is tested is what would lose or overwrite one: the log left
/// behind, the order of the move, a move cut short, and a store already in
/// the directory.
final class StoreMoveTests: XCTestCase {
    private let scratch = StoreScratch()

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    private struct EarlierStore {
        /// Kept open by the caller until the end, as a running app would.
        let writer: ModelContainer
        let provider: ProviderConfig
        let conversations: [Conversation]
    }

    /// A store at the old place as an earlier build leaves one: its three
    /// files copied there while the container that wrote them is still open.
    ///
    /// Copied while open because SQLite folds its log into the main file when
    /// the last connection closes [unverified: SQLite's default, not read in
    /// this repo], and a store whose log is already folded in would move
    /// whole with or without its `-wal`. So before handing it over this
    /// asserts that the `-wal` holds something, and that the main file opened
    /// on its own lacks every conversation just saved — they are in the log
    /// and nowhere else.
    @MainActor
    private func leaveAnEarlierBuildsStore() throws -> EarlierStore {
        let writing = scratch.root.appending(path: "writer/ggchat.store")
        try FileManager.default.createDirectory(
            at: writing.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try scratch.container(at: writing)
        let store = SwiftDataStore(container: writer)
        let provider = ProviderConfig(
            name: "home", kind: .openAICompatible(baseURL: URL(string: "http://home/v1")!), defaultModel: "m")
        try store.save(provider: provider)
        let conversations = StoreScratch.conversations(3, providerID: provider.id)
        for conversation in conversations {
            try store.save(conversation: conversation)
        }

        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            try FileManager.default.copyItem(
                at: URL(filePath: writing.path(percentEncoded: false) + suffix),
                to: scratch.support.appending(path: "ggchat.store" + suffix))
        }

        let log = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: scratch.support.appending(path: "ggchat.store-wal").path(percentEncoded: false))[.size]
                as? NSNumber)
        XCTAssertGreaterThan(log.intValue, 0, "the log was empty, so leaving it behind would lose nothing")
        let alone = scratch.root.appending(path: "alone/ggchat.store")
        try FileManager.default.createDirectory(
            at: alone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: scratch.support.appending(path: "ggchat.store"), to: alone)
        XCTAssertEqual(
            try SwiftDataStore(container: scratch.container(at: alone)).loadConversations(), [],
            "the main file already held the conversations, so this proves nothing about the log")
        return EarlierStore(writer: writer, provider: provider, conversations: conversations)
    }

    /// Every conversation and provider an earlier build kept arrives in the
    /// directory, including the ones only its log held, the `-wal` first,
    /// then the `-shm`, then the main file, and nothing is left at the old
    /// place. The move logs no error, and its line names no path and no
    /// message.
    @MainActor
    func testAStoreFromAnEarlierBuildMovesInWithEveryConversation() throws {
        let earlier = try leaveAnEarlierBuildsStore()
        let log = CapturingLogSink()
        var order: [String] = []

        let opened = SwiftDataStore.open(
            at: scratch.location,
            mover: { from, to in
                order.append(from.lastPathComponent)
                try StoreDirectory.renameWithoutReplacing(from, to)
            },
            log: log)

        XCTAssertNil(opened.notice)
        XCTAssertEqual(order, ["ggchat.store-wal", "ggchat.store-shm", "ggchat.store"])
        let moved = SwiftDataStore(container: opened.container)
        XCTAssertEqual(Set(try moved.loadConversations()), Set(earlier.conversations), "a conversation was lost")
        XCTAssertEqual(try moved.loadProviders(), [earlier.provider])
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertFalse(
                scratch.exists(scratch.support.appending(path: "ggchat.store" + suffix)),
                "ggchat.store\(suffix) was left at the old place")
        }
        XCTAssertFalse(log.lines.isEmpty, "the move went unlogged")
        XCTAssertFalse(log.lines.contains { $0.hasPrefix("[error]") }, "an error was logged: \(log.lines)")
        for line in log.lines {
            XCTAssertFalse(line.contains(scratch.root.path(percentEncoded: false)), "a log line names a path: \(line)")
            XCTAssertFalse(line.contains("question") || line.contains("answer"), "a log line names a message: \(line)")
        }
        withExtendedLifetime(earlier.writer) {}
    }

    /// A store an earlier build left as its main file alone, with no `-wal`
    /// and no `-shm` beside it, moves in with every conversation: the move
    /// takes the files that are there and does not ask for all three. Its log
    /// is folded in first, and the main file is checked to hold everything
    /// before the move. Whether SwiftData ever leaves a store this way is
    /// [unverified].
    @MainActor
    func testAStoreLeftAsItsMainFileAloneMovesInWithEveryConversation() throws {
        let earlier = try leaveAnEarlierBuildsStore()
        let main = scratch.support.appending(path: "ggchat.store")
        try scratch.foldLogIntoMainFile(main)
        XCTAssertEqual(scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }, ["ggchat.store"])
        let alone = scratch.root.appending(path: "folded/ggchat.store")
        try FileManager.default.createDirectory(
            at: alone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: main, to: alone)
        XCTAssertEqual(
            Set(try SwiftDataStore(container: scratch.container(at: alone)).loadConversations()),
            Set(earlier.conversations), "the main file did not hold every conversation before the move")

        let opened = SwiftDataStore.open(at: scratch.location, log: NoopLogSink())

        XCTAssertNil(opened.notice, "a store without its -wal and -shm did not move in")
        let moved = SwiftDataStore(container: opened.container)
        XCTAssertEqual(Set(try moved.loadConversations()), Set(earlier.conversations), "a conversation was lost")
        XCTAssertEqual(try moved.loadProviders(), [earlier.provider])
        XCTAssertEqual(scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }, [])
        withExtendedLifetime(earlier.writer) {}
    }

    /// A move that fails after its first file leaves the main file at the old
    /// place — the log went first — so that launch runs from memory and says
    /// so, and marks what it left there out of the backup. The next launch,
    /// with nothing run in between, finds a store still to move and finishes.
    /// Had the main file gone first, the next launch would open it without
    /// its log.
    @MainActor
    func testAMoveCutShortFinishesOnTheNextLaunch() throws {
        let earlier = try leaveAnEarlierBuildsStore()
        let location = scratch.location
        let leftBehind = ["ggchat.store", "ggchat.store-shm"].map { scratch.support.appending(path: $0) }
        for url in leftBehind {
            XCTAssertNotEqual(try scratch.isExcludedFromBackup(url), true, "\(url.lastPathComponent) began marked")
        }
        var moves = 0

        let cutShort = SwiftDataStore.open(
            at: location,
            mover: { from, to in
                moves += 1
                guard moves == 1 else { throw CocoaError(.fileWriteUnknown) }
                try StoreDirectory.renameWithoutReplacing(from, to)
            },
            log: NoopLogSink())

        XCTAssertEqual(cutShort.notice?.keptInMemory, true)
        XCTAssertTrue(
            scratch.exists(scratch.support.appending(path: "ggchat.store")),
            "the main file moved before the rest of the store")
        XCTAssertFalse(scratch.exists(location.storeURL))
        for url in leftBehind {
            XCTAssertEqual(
                try scratch.isExcludedFromBackup(url), true,
                "\(url.lastPathComponent), left at the old place by a failed move, would ride the next backup")
        }

        let finished = SwiftDataStore.open(at: location, log: NoopLogSink())

        XCTAssertNil(finished.notice)
        let moved = SwiftDataStore(container: finished.container)
        XCTAssertEqual(Set(try moved.loadConversations()), Set(earlier.conversations), "a conversation was lost")
        XCTAssertEqual(try moved.loadProviders(), [earlier.provider])
        XCTAssertEqual(scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }, [])
        withExtendedLifetime(earlier.writer) {}
    }

    /// An older build run after the move makes a new store at the old place.
    /// At the next launch of this build, the step that moves stores leaves
    /// the directory's files byte for byte as they were, and the older store
    /// where it is, marked out of the backup. The launch then opens the
    /// directory's store, leaves the older one's bytes as they were, and
    /// reports it, as does the launch after. The line that logs it names no
    /// path. Both stores stay open in their writers throughout, so that no
    /// connection closing mid-test changes a file.
    @MainActor
    func testAStoreAlreadyInTheDirectoryIsNeverReplacedByAnOlderOne() throws {
        let location = scratch.location
        let kept = StoreScratch.conversations(2, providerID: UUID())
        let first = SwiftDataStore.open(at: location, log: NoopLogSink())
        let store = SwiftDataStore(container: first.container)
        for conversation in kept {
            try store.save(conversation: conversation)
        }
        let earlier = try leaveAnEarlierBuildsStore()
        let leftBehind = scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }
        XCTAssertTrue(leftBehind.contains("ggchat.store"))
        let before = try scratch.contents(of: location.directory)

        let log = CapturingLogSink()
        XCTAssertTrue(try location.prepare(mover: StoreDirectory.renameWithoutReplacing, log: log))

        XCTAssertEqual(try scratch.contents(of: location.directory), before, "the store in the directory was touched")
        XCTAssertFalse(log.lines.isEmpty, "the store left behind went unlogged")
        for line in log.lines {
            XCTAssertFalse(line.contains(scratch.root.path(percentEncoded: false)), "a log line names a path: \(line)")
        }
        XCTAssertEqual(scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }, leftBehind)
        for name in leftBehind {
            XCTAssertEqual(
                try scratch.isExcludedFromBackup(scratch.support.appending(path: name)), true,
                "\(name) at the old place would ride the next backup")
        }

        let older = try leftBehind.map { try Data(contentsOf: scratch.support.appending(path: $0)) }
        let opened = SwiftDataStore.open(at: location, log: NoopLogSink())

        XCTAssertEqual(opened.notice, StoreNotice(keptInMemory: false, olderStoreLeftBehind: true))
        XCTAssertEqual(Set(try SwiftDataStore(container: opened.container).loadConversations()), Set(kept))
        XCTAssertEqual(
            try leftBehind.map { try Data(contentsOf: scratch.support.appending(path: $0)) }, older,
            "the older store was opened")
        XCTAssertEqual(SwiftDataStore.open(at: location, log: NoopLogSink()).notice, opened.notice)
        withExtendedLifetime((store, earlier.writer)) {}
    }

    /// A file of the store's already in the directory with no main file
    /// beside it — a move cut short, and then an older build that wrote a new
    /// log at the old place — is not replaced: the move stops, both logs stay
    /// as they were, and the launch runs from memory rather than open either.
    /// The line it logs gives the rename's error, `EEXIST`.
    @MainActor
    func testAMoveStopsRatherThanReplaceAFileAlreadyInTheDirectory() throws {
        let location = scratch.location
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try Data("main".utf8).write(to: scratch.support.appending(path: "ggchat.store"))
        try Data("the older build's log".utf8).write(to: scratch.support.appending(path: "ggchat.store-wal"))
        try Data("the log that moved".utf8).write(to: location.directory.appending(path: "ggchat.store-wal"))
        let log = CapturingLogSink()

        let opened = SwiftDataStore.open(at: location, log: log)

        XCTAssertEqual(opened.notice?.keptInMemory, true)
        XCTAssertEqual(
            try scratch.contents(of: location.directory), ["ggchat.store-wal": Data("the log that moved".utf8)])
        XCTAssertEqual(try Data(contentsOf: scratch.support.appending(path: "ggchat.store")), Data("main".utf8))
        XCTAssertEqual(
            try Data(contentsOf: scratch.support.appending(path: "ggchat.store-wal")),
            Data("the older build's log".utf8))
        XCTAssertTrue(log.lines.contains { $0.contains("(NSPOSIXErrorDomain 17)") }, "\(log.lines)")
    }
}
