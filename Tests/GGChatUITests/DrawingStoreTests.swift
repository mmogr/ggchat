import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before drawing declared them, for opening a store
/// across the change in both directions.
enum BeforeDrawing {
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

/// That a question was sent with Draw, and how a reply's run writes its
/// events, are kept with their turns in two optional columns, written only
/// for a turn that has them, and a store opens across the change that added
/// them.
@MainActor
final class DrawingStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation() -> Conversation {
        Conversation(
            title: "a fox", providerID: UUID(), model: "m",
            messages: [
                Message(role: .user, content: "a fox in snow", createdAt: stamp, draws: true),
                Message(
                    role: .assistant, content: "", isPartial: true, createdAt: stamp, runID: "run-1", runCursor: 2,
                    runFrames: .agent),
                Message(role: .user, content: "plain", createdAt: stamp),
            ], createdAt: stamp, updatedAt: stamp)
    }

    /// Both words outlive a reopening, and a turn with neither writes
    /// neither column, as a row from before them holds neither. A write
    /// that changes nothing marks no row.
    func testThatAQuestionDrewAndHowItsRunWritesOutliveAReopening() throws {
        let container = SwiftDataStore.inMemoryContainer()
        let store = SwiftDataStore(container: container)
        var kept = conversation()
        try store.save(conversation: kept)
        let read = try XCTUnwrap(try SwiftDataStore(container: container).loadConversations().first)
        XCTAssertEqual(read.messages.map(\.draws), [true, false, false])
        XCTAssertEqual(read.messages.map(\.runFrames), [nil, .agent, nil])
        XCTAssertEqual(read.messages, kept.messages)

        let rows = try store.context.fetch(FetchDescriptor<MessageRecord>()).sorted { $0.order < $1.order }
        XCTAssertEqual(rows.map(\.draws), [true, nil, nil])
        XCTAssertEqual(rows.map(\.runFrames), [nil, "agent", nil])
        try store.write(read)
        XCTAssertFalse(store.context.hasChanges, "a write that changed nothing marked a row")

        // The run ends, and a retry that can no longer draw unmarks.
        kept.messages[0].draws = false
        kept.messages[1].runID = nil
        kept.messages[1].runCursor = nil
        kept.messages[1].runFrames = nil
        try store.save(conversation: kept)
        XCTAssertEqual(rows.map(\.draws), [nil, nil, nil])
        XCTAssertEqual(rows.map(\.runFrames), [nil, nil, nil])

        // A word for the frames this build does not know reads as none.
        rows[1].runFrames = "something-new"
        try store.context.save()
        XCTAssertEqual(try store.loadConversations().first?.messages.map(\.runFrames), [nil, nil, nil])
    }

    /// A store the build before drawing wrote opens in this one, no turn
    /// drawing. One this build wrote opens in this build with both words,
    /// and under the earlier schema with its turns. The earlier build drops
    /// the columns it does not know, so this build then opens that store
    /// with neither.
    func testAStoreOpensAcrossTheDrawingColumnsInBothDirections() throws {
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
            let written = try container(BeforeDrawing.schema, at: older)
            let record = BeforeDrawing.ConversationRecord(id: UUID(), title: "before", createdAt: stamp)
            written.mainContext.insert(record)
            let message = BeforeDrawing.MessageRecord(
                id: UUID(), role: "user", content: "hello", createdAt: stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertEqual(read.messages.map(\.draws), [false])
        XCTAssertEqual(read.messages.map(\.runFrames), [nil])

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: conversation())
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            let kept = try XCTUnwrap(try store.loadConversations().first)
            XCTAssertEqual(kept.messages.map(\.draws), [true, false, false])
            XCTAssertEqual(kept.messages.map(\.runFrames), [nil, .agent, nil])
        }
        do {
            let earlier = try container(BeforeDrawing.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeDrawing.MessageRecord>())
            XCTAssertEqual(rows.sorted { $0.order < $1.order }.map(\.content), ["a fox in snow", "", "plain"])
            XCTAssertEqual(rows.compactMap(\.runID), ["run-1"])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.messages.map(\.content), ["a fox in snow", "", "plain"])
        XCTAssertEqual(back.messages.map(\.draws), [false, false, false])
        XCTAssertEqual(back.messages.map(\.runFrames), [nil, nil, nil])
    }
}
