import Foundation
import GGChatCore
import SQLite3
import SwiftData
import XCTest

@testable import GGChatUI

/// The three rows as builds before `ProviderRecord.lastHeard` wrote them, so
/// a store can be left the way those builds left it. Nested, so each keeps
/// its entity's name.
private enum BeforeLastHeard {
    @Model
    final class ProviderRecord {
        @Attribute(.unique) var uuid: UUID
        var name: String
        var kindData: Data
        var defaultModel: String?
        var createdAt: Date

        init(uuid: UUID, name: String, kindData: Data, createdAt: Date) {
            self.uuid = uuid
            self.name = name
            self.kindData = kindData
            self.defaultModel = nil
            self.createdAt = createdAt
        }
    }

    @Model
    final class ConversationRecord {
        @Attribute(.unique) var uuid: UUID
        var title: String
        var providerID: UUID?
        var model: String?
        var systemPrompt: String?
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
        var messages: [MessageRecord] = []

        init(uuid: UUID, createdAt: Date) {
            self.uuid = uuid
            self.title = ""
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }

    @Model
    final class MessageRecord {
        @Attribute(.unique) var uuid: UUID
        var role: String
        var content: String
        var reasoning: String?
        var isPartial: Bool
        var failureData: Data?
        var createdAt: Date
        var order: Int
        var conversation: ConversationRecord?

        init(uuid: UUID, createdAt: Date) {
            self.uuid = uuid
            self.role = "user"
            self.content = ""
            self.isPartial = false
            self.createdAt = createdAt
            self.order = 0
        }
    }
}

/// A network watcher that never reports a change.
private struct StillNetwork: NetworkPathWatching {
    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

/// When a pipe's machine was last heard is kept in the store, in the
/// directory the store lives in, and a store written before it opens.
final class LastHeardStoreTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let heardAt = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func makeModel(_ store: any Store, now: Date) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "LastHeardStoreTests.\(UUID().uuidString)")!
        return AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            networkWatcher: StillNetwork(), diagnostics: Diagnostics(defaults: defaults), now: { now })
    }

    private struct SQLiteRefused: Error, CustomStringConvertible {
        let step: String
        var description: String { "SQLite refused at \(step)" }
    }

    /// The names of the columns SQLite holds for the provider rows.
    private func providerColumns(in url: URL) throws -> [String] {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path(percentEncoded: false), &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { throw SQLiteRefused(step: "open") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(ZPROVIDERRECORD)", -1, &statement, nil) == SQLITE_OK
        else { throw SQLiteRefused(step: "prepare") }
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.append(String(cString: sqlite3_column_text(statement, 1)))
        }
        return columns
    }

    @MainActor
    func testTheTimeSurvivesARelaunchOfTheStore() async throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)))
        do {
            let opened = SwiftDataStore.open(at: scratch.location, log: NoopLogSink())
            XCTAssertNil(opened.notice, "the store was not kept on disk")
            let model = makeModel(SwiftDataStore(container: opened.container), now: heardAt)
            try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
            await model.connectPipe(for: config)
            for _ in 0..<200 where model.pipeStatus(for: config.id) != .direct { await Task.yield() }
            XCTAssertEqual(model.lastHeard(for: config.id), heardAt)
            await model.disconnectPipe(for: config.id)
        }

        let reopened = SwiftDataStore.open(at: scratch.location, log: NoopLogSink())
        let model = makeModel(SwiftDataStore(container: reopened.container), now: heardAt.addingTimeInterval(86_400))
        model.load()
        XCTAssertEqual(model.providers.map(\.id), [config.id])
        XCTAssertEqual(model.lastHeard(for: config.id), heardAt, "the time did not outlive the relaunch")
        XCTAssertTrue(
            try providerColumns(in: scratch.location.storeURL).contains("ZLASTHEARD"),
            "the time is not a column of the store in the store's directory")
    }

    /// An existing store has no such column. It opens on disk, and not in
    /// memory, with the column added and every row reading nil.
    @MainActor
    func testAStoreWrittenBeforeTheColumnOpensWithItEmpty() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        let location = scratch.location
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let id = UUID()
        do {
            let schema = Schema([
                BeforeLastHeard.ProviderRecord.self, BeforeLastHeard.ConversationRecord.self,
                BeforeLastHeard.MessageRecord.self,
            ])
            let configuration = ModelConfiguration(
                "ggchat", schema: schema, url: location.storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let kindData = try JSONEncoder().encode(ProviderConfig.Kind.pipe(ticketDigest: "abc"))
            container.mainContext.insert(
                BeforeLastHeard.ProviderRecord(uuid: id, name: "home", kindData: kindData, createdAt: heardAt))
            let conversation = BeforeLastHeard.ConversationRecord(uuid: UUID(), createdAt: heardAt)
            conversation.messages = [BeforeLastHeard.MessageRecord(uuid: UUID(), createdAt: heardAt)]
            container.mainContext.insert(conversation)
            try container.mainContext.save()
        }
        let before = try providerColumns(in: location.storeURL)
        XCTAssertTrue(before.contains("ZNAME"), "the earlier store's provider rows were not read: \(before)")
        XCTAssertFalse(before.contains("ZLASTHEARD"), "the earlier store already had the column")

        let opened = SwiftDataStore.open(at: location, log: NoopLogSink())
        XCTAssertNil(opened.notice, "a store written before the column fell back to memory")
        let store = SwiftDataStore(container: opened.container)
        XCTAssertEqual(try store.loadProviders().map(\.id), [id])
        XCTAssertEqual(try store.loadConversations().map(\.messages.count), [1], "the earlier conversation was lost")
        XCTAssertEqual(try store.loadLastHeard(), [:])
        try store.save(lastHeard: heardAt, forProvider: id)
        XCTAssertEqual(try store.loadLastHeard(), [id: heardAt])
    }
}
