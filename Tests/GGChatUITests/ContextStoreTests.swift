import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before the context reading declared them, for
/// opening a store across the change in both directions.
enum BeforeContext {
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
        @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
        var messages: [MessageRecord] = []

        init(id: UUID, title: String, model: String?, createdAt: Date) {
            self.uuid = id
            self.title = title
            self.model = model
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

/// A conversation's context reading is kept with it, written only when it
/// changes, and a store opens across the change that added it.
@MainActor
final class ContextStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation(_ title: String, _ context: ContextReading?) -> Conversation {
        Conversation(
            title: title, providerID: UUID(), model: "m",
            messages: [Message(role: .assistant, content: "done", createdAt: stamp)], createdAt: stamp,
            updatedAt: stamp, context: context)
    }

    private func row(_ id: UUID, in store: SwiftDataStore) throws -> ConversationRecord {
        try XCTUnwrap(try store.context.fetch(FetchDescriptor<ConversationRecord>()).first { $0.uuid == id })
    }

    /// The reading is read back as written, on a new row and an existing
    /// one, every part of it, and cleared as written; a conversation with
    /// none writes none. Saving one that has not changed marks no row, and
    /// a changed one marks the conversation's alone.
    func testTheReadingIsKeptAndAnUnchangedOneMarksNoRow() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let full = try XCTUnwrap(
            ContextReading(
                promptTokens: 31_000, completionTokens: 400, contextSize: 32_768, trimmedMessages: 3,
                finishReason: "length", model: "qwen3-8b"))
        var kept = conversation("kept", full)
        let plain = conversation("plain", nil)
        try store.save(conversation: kept)
        try store.save(conversation: plain)
        func read() throws -> [String: ContextReading?] {
            Dictionary(uniqueKeysWithValues: try store.loadConversations().map { ($0.title, $0.context) })
        }
        XCTAssertEqual(try read(), ["kept": full, "plain": nil])
        XCTAssertNil(try row(plain.id, in: store).contextData, "a conversation with no reading wrote one")
        let loaded = try XCTUnwrap(try store.loadConversations().first { $0.id == kept.id }?.context)
        XCTAssertEqual(loaded.used, 31_400)
        XCTAssertEqual(loaded.size, 32_768)
        XCTAssertEqual(loaded.trimmed, 3)
        XCTAssertTrue(loaded.cutOff)
        XCTAssertEqual(loaded.model, "qwen3-8b")

        func changed() -> [String] {
            store.context.changedModelsArray.compactMap { model in
                (model as? ConversationRecord).map { "conversation \($0.title)" } ?? "something else"
            }
        }
        try store.write(kept)
        try store.write(try XCTUnwrap(try store.loadConversations().first { $0.id == kept.id }))
        try store.write(plain)
        XCTAssertEqual(changed(), [], "a write marked a row whose reading had not changed")
        XCTAssertFalse(store.context.hasChanges)

        let next = try XCTUnwrap(
            ContextReading(promptTokens: 8_000, completionTokens: 200, contextSize: 32_768, model: "qwen3-8b"))
        kept.context = next
        try store.write(kept)
        XCTAssertEqual(changed(), ["conversation kept"])
        try store.context.save()
        XCTAssertEqual(try read(), ["kept": next, "plain": nil])

        kept.context = nil
        try store.save(conversation: kept)
        XCTAssertEqual(try read(), ["kept": nil, "plain": nil])
        XCTAssertNil(try row(kept.id, in: store).contextData, "a cleared reading left its bytes")

        // Bytes this build cannot read are no reading, not a store that fails,
        // and neither are bytes whose numbers are no reading: a size of zero
        // would divide by it, and a count no context holds would overflow.
        func stored(used: String, size: Int) -> Data {
            Data(#"{"used":\#(used),"size":\#(size),"trimmed":0,"cutOff":false,"model":"m"}"#.utf8)
        }
        try row(plain.id, in: store).contextData = stored(used: "8200", size: 32_768)
        try store.context.save()
        XCTAssertEqual(
            try store.loadConversations().first { $0.id == plain.id }?.context?.percent, 25,
            "bytes of this shape with real counts did not read")
        let unreadable = [
            Data(#"{"used":true}"#.utf8), stored(used: "8200", size: 0), stored(used: "8200", size: -1),
            stored(used: "\(Int.max)", size: 32_768), stored(used: "-1", size: 32_768),
            stored(used: "8200", size: .max),
        ]
        for bytes in unreadable {
            try row(plain.id, in: store).contextData = bytes
            try store.context.save()
            XCTAssertEqual(try read(), ["kept": nil, "plain": nil], String(decoding: bytes, as: UTF8.self))
        }
    }

    /// A store the build before the reading wrote opens in this one, its
    /// conversations with none. One this build wrote, a reading kept, opens
    /// in this build with the reading, and under the earlier schema with the
    /// conversation and its messages. The earlier build drops the column it
    /// does not know, so this build then opens that store with the
    /// conversation and no reading, until a reply leaves one.
    func testAStoreOpensAcrossTheReadingInBothDirections() throws {
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
            let written = try container(BeforeContext.schema, at: older)
            let record = BeforeContext.ConversationRecord(id: UUID(), title: "before", model: "m", createdAt: stamp)
            written.mainContext.insert(record)
            let message = BeforeContext.MessageRecord(
                id: UUID(), role: "assistant", content: "hello", createdAt: stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.title, "before")
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertNil(read.context)

        let newer = scratch.support.appending(path: "newer.store")
        let reading = try XCTUnwrap(
            ContextReading(promptTokens: 8_000, completionTokens: 200, contextSize: 32_768, model: "m"))
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: conversation("with a reading", reading))
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadConversations().map(\.context), [reading])
        }
        do {
            let earlier = try container(BeforeContext.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeContext.ConversationRecord>())
            XCTAssertEqual(rows.map(\.title), ["with a reading"])
            XCTAssertEqual(rows.first?.messages.map(\.content), ["done"])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.title, "with a reading")
        XCTAssertEqual(back.messages.map(\.content), ["done"])
        XCTAssertNil(back.context)
    }
}
