import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before the Tools switch declared them, for opening
/// a store across the change in both directions.
enum BeforeTools {
    @Model
    final class ConversationRecord {
        @Attribute(.unique) var uuid: UUID
        var title: String
        var providerID: UUID?
        var model: String?
        var systemPrompt: String?
        var createdAt: Date
        var updatedAt: Date
        var hasUnreadReply: Bool?
        var contextData: Data?
        var thinkingOff: Bool?
        var branchOf: UUID?
        var family: UUID?
        var imageModelID: Int?
        @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
        var messages: [MessageRecord] = []

        init(id: UUID, title: String, createdAt: Date) {
            self.uuid = id
            self.title = title
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
        var runID: String?
        var runCursor: Int?
        var imagesData: Data?
        var originID: UUID?
        var draws: Bool?
        var runFrames: String?
        var exchangesData: Data?
        var createdAt: Date
        var order: Int
        var conversation: ConversationRecord?

        init(id: UUID, role: String, content: String, createdAt: Date, order: Int) {
            self.uuid = id
            self.role = role
            self.content = content
            self.isPartial = false
            self.createdAt = createdAt
            self.order = order
        }
    }

    static let schema = Schema([ProviderRecord.self, ConversationRecord.self, MessageRecord.self, ImageRecord.self])
}

/// A conversation's Tools choice is kept with it in one optional column,
/// written only for a conversation that turned them off, and a store opens
/// across the change that added it.
@MainActor
final class ToolsStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation(_ title: String, off: Bool) -> Conversation {
        Conversation(
            title: title, providerID: UUID(), model: "m",
            messages: [Message(role: .assistant, content: "done", createdAt: stamp)], createdAt: stamp,
            updatedAt: stamp, toolsOff: off)
    }

    private func row(_ id: UUID, in store: SwiftDataStore) throws -> ConversationRecord {
        try XCTUnwrap(try store.context.fetch(FetchDescriptor<ConversationRecord>()).first { $0.uuid == id })
    }

    /// The choice outlives a reopening, off and on again. A conversation
    /// with the tools on writes no column, a write that changes nothing
    /// marks no row, and a row that says nothing reads as on.
    func testTheChoiceOutlivesAReopeningAndAnUnchangedOneMarksNoRow() throws {
        let container = SwiftDataStore.inMemoryContainer()
        let store = SwiftDataStore(container: container)
        var quiet = conversation("quiet", off: true)
        let plain = conversation("plain", off: false)
        try store.save(conversation: quiet)
        try store.save(conversation: plain)
        func read() throws -> [String: Bool] {
            let reopened = SwiftDataStore(container: container)
            return Dictionary(uniqueKeysWithValues: try reopened.loadConversations().map { ($0.title, $0.toolsOff) })
        }
        XCTAssertEqual(try read(), ["quiet": true, "plain": false])
        XCTAssertEqual(try row(quiet.id, in: store).toolsOff, true)
        XCTAssertNil(try row(plain.id, in: store).toolsOff, "a conversation with the tools on wrote the column")

        try store.write(quiet)
        try store.write(try XCTUnwrap(try store.loadConversations().first { $0.id == quiet.id }))
        try store.write(plain)
        XCTAssertFalse(store.context.hasChanges, "a write marked a row whose choice had not changed")

        quiet.toolsOff = false
        try store.save(conversation: quiet)
        XCTAssertNil(try row(quiet.id, in: store).toolsOff)
        XCTAssertEqual(try read(), ["quiet": false, "plain": false])
        quiet.toolsOff = true
        try store.save(conversation: quiet)
        XCTAssertEqual(try read(), ["quiet": true, "plain": false])
    }

    /// A store the build before wrote opens in this one, its conversation
    /// with the tools on. One this build wrote opens in this build with the
    /// tools off, and under the earlier schema with its turns. The earlier
    /// build drops the column it does not know, so this build then opens
    /// that store with the tools on again.
    func testAStoreOpensAcrossTheToolsColumnInBothDirections() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
            let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let older = scratch.support.appending(path: "older.store")
        do {
            // Held: a context whose container has gone traps on its next use.
            let written = try container(BeforeTools.schema, at: older)
            let record = BeforeTools.ConversationRecord(id: UUID(), title: "before", createdAt: stamp)
            written.mainContext.insert(record)
            let message = BeforeTools.MessageRecord(
                id: UUID(), role: "assistant", content: "hello", createdAt: stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.title, "before")
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertFalse(read.toolsOff)

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: conversation("switched off", off: true))
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadConversations().map(\.toolsOff), [true])
        }
        do {
            let earlier = try container(BeforeTools.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeTools.ConversationRecord>())
            XCTAssertEqual(rows.map(\.title), ["switched off"])
            XCTAssertEqual(rows.first?.messages.map(\.content), ["done"])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.title, "switched off")
        XCTAssertEqual(back.messages.map(\.content), ["done"])
        XCTAssertFalse(back.toolsOff)
    }
}
