import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before a conversation chose its image model
/// declared them, for opening a store across the change in both directions.
enum BeforeImageChoice {
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

/// The image model a conversation chose is kept with it in one optional
/// column, written only for a conversation that chose one, and a store
/// opens across the change that added it.
@MainActor
final class ImageModelStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation(_ chosen: UInt64?) -> Conversation {
        Conversation(
            title: "a fox", providerID: UUID(), model: "m",
            messages: [Message(role: .user, content: "a fox in snow", createdAt: stamp, draws: true)],
            createdAt: stamp, updatedAt: stamp, imageModelID: chosen)
    }

    /// The choice outlives a reopening, a conversation with none writes no
    /// column, a write that changes nothing marks no row, and a choice put
    /// back to the default empties the column.
    func testTheChoiceOutlivesAReopening() throws {
        let container = SwiftDataStore.inMemoryContainer()
        let store = SwiftDataStore(container: container)
        var chose = conversation(7)
        let unchosen = conversation(nil)
        try store.save(conversation: chose)
        try store.save(conversation: unchosen)
        let read = try SwiftDataStore(container: container).loadConversations()
        XCTAssertEqual(read.first { $0.id == chose.id }?.imageModelID, 7)
        XCTAssertNil(try XCTUnwrap(read.first { $0.id == unchosen.id }).imageModelID)

        let rows = try store.context.fetch(FetchDescriptor<ConversationRecord>())
        XCTAssertEqual(rows.first { $0.uuid == chose.id }?.imageModelID, 7)
        XCTAssertNil(try XCTUnwrap(rows.first { $0.uuid == unchosen.id }).imageModelID)
        try store.write(try XCTUnwrap(read.first { $0.id == chose.id }))
        XCTAssertFalse(store.context.hasChanges, "a write that changed nothing marked a row")

        chose.imageModelID = nil
        try store.save(conversation: chose)
        XCTAssertNil(try XCTUnwrap(rows.first { $0.uuid == chose.id }).imageModelID)
        XCTAssertNil(try XCTUnwrap(try store.loadConversations().first { $0.id == chose.id }).imageModelID)
    }

    /// A store the build before wrote opens in this one, its conversation
    /// with no choice. One this build wrote opens in this build with the
    /// choice, and under the earlier schema with its turns. The earlier
    /// build drops the column it does not know, so this build then opens
    /// that store with no choice.
    func testAStoreOpensAcrossTheImageModelColumnInBothDirections() throws {
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
            let written = try container(BeforeImageChoice.schema, at: older)
            let record = BeforeImageChoice.ConversationRecord(id: UUID(), title: "before", createdAt: stamp)
            written.mainContext.insert(record)
            let message = BeforeImageChoice.MessageRecord(
                id: UUID(), role: "user", content: "hello", createdAt: stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.title, "before")
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertNil(read.imageModelID)

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: conversation(7))
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadConversations().first?.imageModelID, 7)
        }
        do {
            let earlier = try container(BeforeImageChoice.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeImageChoice.MessageRecord>())
            XCTAssertEqual(rows.map(\.content), ["a fox in snow"])
            XCTAssertEqual(rows.map(\.draws), [true])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.messages.map(\.content), ["a fox in snow"])
        XCTAssertNil(back.imageModelID)
    }
}
