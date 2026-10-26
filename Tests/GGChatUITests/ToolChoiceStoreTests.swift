import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before each conversation picked its servers
/// declared them, with the Tools switch's column, for opening a store across
/// the change in both directions.
enum BeforeToolChoice {
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
        var toolsOff: Bool?
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

/// A conversation's choice of servers is kept with it in one optional
/// column, written only for a choice that is not a new conversation's, and
/// a store opens across the change that replaced the Tools switch's column.
@MainActor
final class ToolChoiceStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation(_ title: String, choice: ToolChoice) -> Conversation {
        Conversation(
            title: title, providerID: UUID(), model: "m",
            messages: [Message(role: .assistant, content: "done", createdAt: stamp)], createdAt: stamp,
            updatedAt: stamp, toolChoice: choice)
    }

    private func row(_ id: UUID, in store: SwiftDataStore) throws -> ConversationRecord {
        try XCTUnwrap(try store.context.fetch(FetchDescriptor<ConversationRecord>()).first { $0.uuid == id })
    }

    /// The choice outlives a reopening, changed and back. A new
    /// conversation's writes no column, a write that changes nothing marks
    /// no row, and a row that says nothing reads as a new conversation's.
    func testTheToolChoiceOutlivesAReopeningAndAnUnchangedOneMarksNoRow() throws {
        let container = SwiftDataStore.inMemoryContainer()
        let store = SwiftDataStore(container: container)
        let picked = ToolChoice(off: true, picked: [9, 3], seen: [3, 9, 12])
        var quiet = conversation("quiet", choice: picked)
        let plain = conversation("plain", choice: ToolChoice())
        try store.save(conversation: quiet)
        try store.save(conversation: plain)
        func read() throws -> [String: ToolChoice] {
            let reopened = SwiftDataStore(container: container)
            return Dictionary(uniqueKeysWithValues: try reopened.loadConversations().map { ($0.title, $0.toolChoice) })
        }
        XCTAssertEqual(try read(), ["quiet": picked, "plain": ToolChoice()])
        XCTAssertNotNil(try row(quiet.id, in: store).toolChoiceData)
        XCTAssertNil(try row(plain.id, in: store).toolChoiceData, "a new conversation's choice wrote the column")

        try store.write(quiet)
        try store.write(try XCTUnwrap(try store.loadConversations().first { $0.id == quiet.id }))
        try store.write(plain)
        XCTAssertFalse(store.context.hasChanges, "a write marked a row whose choice had not changed")

        quiet.toolChoice = ToolChoice()
        try store.save(conversation: quiet)
        XCTAssertNil(try row(quiet.id, in: store).toolChoiceData)
        XCTAssertEqual(try read(), ["quiet": ToolChoice(), "plain": ToolChoice()])
        quiet.toolChoice = picked.turned(on: true)
        try store.save(conversation: quiet)
        XCTAssertEqual(try read(), ["quiet": picked.turned(on: true), "plain": ToolChoice()])
    }

    /// Every key of a choice that is not a new conversation's is written,
    /// its sets as sorted lists, and read back as it was.
    func testANonDefaultChoiceRoundTripsEveryKey() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let choice = ToolChoice(off: true, picked: [9, 3], seen: [12, 3])
        let saved = conversation("picked", choice: choice)
        try store.save(conversation: saved)
        let data = try XCTUnwrap(try row(saved.id, in: store).toolChoiceData)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["off", "picked", "seen"])
        XCTAssertEqual(object["picked"] as? [Int], [3, 9])
        XCTAssertEqual(object["seen"] as? [Int], [3, 12])
        XCTAssertEqual(try store.loadConversations().first?.toolChoice, choice)
    }

    /// A store the build before wrote, with its conversation's tools
    /// switched off, opens in this one with a new conversation's choice: the
    /// switch's column is dropped, not read. One this build wrote opens in
    /// this build with its choice, and under the earlier schema with its
    /// turns. The earlier build drops the column it does not know, so this
    /// build then opens that store with a new conversation's choice again.
    func testAStoreOpensAcrossTheToolChoiceColumnInBothDirections() throws {
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
            let written = try container(BeforeToolChoice.schema, at: older)
            let record = BeforeToolChoice.ConversationRecord(id: UUID(), title: "before", createdAt: stamp)
            record.toolsOff = true
            written.mainContext.insert(record)
            let message = BeforeToolChoice.MessageRecord(
                id: UUID(), role: "assistant", content: "hello", createdAt: stamp, order: 0)
            message.conversation = record
            written.mainContext.insert(message)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.title, "before")
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertEqual(read.toolChoice, ToolChoice())

        let choice = ToolChoice(picked: [3], seen: [3])
        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(conversation: conversation("picked", choice: choice))
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadConversations().map(\.toolChoice), [choice])
        }
        do {
            let earlier = try container(BeforeToolChoice.schema, at: newer)
            let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeToolChoice.ConversationRecord>())
            XCTAssertEqual(rows.map(\.title), ["picked"])
            XCTAssertEqual(rows.first?.messages.map(\.content), ["done"])
        }
        let again = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
        let back = try XCTUnwrap(try again.loadConversations().first)
        XCTAssertEqual(back.title, "picked")
        XCTAssertEqual(back.messages.map(\.content), ["done"])
        XCTAssertEqual(back.toolChoice, ToolChoice())
    }
}
