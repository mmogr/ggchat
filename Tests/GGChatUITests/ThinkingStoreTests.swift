import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before the Thinking switch declared them, for
/// opening a store across the change in both directions.
enum BeforeThinking {
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

/// A conversation's Thinking choice is kept with it in one optional column,
/// written only when it changes, and a store opens across the change that
/// added it.
@MainActor
final class ThinkingStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation(_ title: String, off: Bool) -> Conversation {
        Conversation(
            title: title, providerID: UUID(), model: "m",
            messages: [Message(role: .assistant, content: "done", createdAt: stamp)], createdAt: stamp,
            updatedAt: stamp, thinkingOff: off)
    }

    private func row(_ id: UUID, in store: SwiftDataStore) throws -> ConversationRecord {
        try XCTUnwrap(try store.context.fetch(FetchDescriptor<ConversationRecord>()).first { $0.uuid == id })
    }

    /// The choice is read back as written, on a new row and an existing one,
    /// off and on again. Saving a conversation that has not changed marks no
    /// row, a changed choice marks the conversation's alone, and a row that
    /// says nothing reads as on.
    func testTheChoiceIsKeptAndAnUnchangedOneMarksNoRow() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        var quiet = conversation("quiet", off: true)
        let plain = conversation("plain", off: false)
        try store.save(conversation: quiet)
        try store.save(conversation: plain)
        func read() throws -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: try store.loadConversations().map { ($0.title, $0.thinkingOff) })
        }
        XCTAssertEqual(try read(), ["quiet": true, "plain": false])
        XCTAssertEqual(try row(quiet.id, in: store).thinkingOff, true)

        func changed() -> [String] {
            store.context.changedModelsArray.compactMap { model in
                (model as? ConversationRecord).map { "conversation \($0.title)" } ?? "something else"
            }
        }
        try store.write(quiet)
        try store.write(try XCTUnwrap(try store.loadConversations().first { $0.id == quiet.id }))
        try store.write(plain)
        XCTAssertEqual(changed(), [], "a write marked a row whose choice had not changed")
        XCTAssertFalse(store.context.hasChanges)

        quiet.thinkingOff = false
        try store.write(quiet)
        XCTAssertEqual(changed(), ["conversation quiet"])
        try store.context.save()
        XCTAssertEqual(try read(), ["quiet": false, "plain": false])
        quiet.thinkingOff = true
        try store.save(conversation: quiet)
        XCTAssertEqual(try read(), ["quiet": true, "plain": false])

        // A row from before the column says nothing, which is on.
        try row(quiet.id, in: store).thinkingOff = nil
        try store.context.save()
        XCTAssertEqual(try read(), ["quiet": false, "plain": false])
    }

    /// A store the build before the switch wrote opens in this one, its
    /// conversations switched on. One this build wrote, a conversation
    /// switched off, opens in this build still off, and under the earlier
    /// schema with the conversation and its messages. The earlier build
    /// drops the column it does not know, so this build then opens that
    /// store with the conversation switched on again.
    func testAStoreOpensAcrossTheChoiceInBothDirections() throws {
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
            let written = try container(BeforeThinking.schema, at: older)
            let record = BeforeThinking.ConversationRecord(id: UUID(), title: "before", model: "m", createdAt: stamp)
            written.mainContext.insert(record)
            let message = BeforeThinking.MessageRecord(
                id: UUID(), role: "assistant", content: "hello", createdAt: stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.title, "before")
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertFalse(read.thinkingOff)

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: conversation("switched off", off: true))
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadConversations().map(\.thinkingOff), [true])
        }
        do {
            let earlier = try container(BeforeThinking.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeThinking.ConversationRecord>())
            XCTAssertEqual(rows.map(\.title), ["switched off"])
            XCTAssertEqual(rows.first?.messages.map(\.content), ["done"])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.title, "switched off")
        XCTAssertEqual(back.messages.map(\.content), ["done"])
        XCTAssertFalse(back.thinkingOff)
    }
}
