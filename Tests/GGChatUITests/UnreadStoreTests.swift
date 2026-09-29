import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A conversation's rows as the build before the unread mark declared them,
/// for opening a store across that change in both directions.
enum BeforeUnread {
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

    static let schema = Schema([EarlierBuild.ProviderRecord.self, ConversationRecord.self, MessageRecord.self])
}

/// The unread mark outlives the app being closed, and a store opens across
/// the change that added it.
final class UnreadStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The mark is read back as written, on a new row and on an existing one,
    /// and cleared as written.
    @MainActor
    func testTheUnreadMarkIsKeptWithItsConversation() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        var marked = Conversation(title: "marked", createdAt: stamp, updatedAt: stamp, hasUnreadReply: true)
        let plain = Conversation(title: "plain", createdAt: stamp, updatedAt: stamp)
        try store.save(conversation: marked)
        try store.save(conversation: plain)
        func read() throws -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: try store.loadConversations().map { ($0.title, $0.hasUnreadReply) })
        }
        XCTAssertEqual(try read(), ["marked": true, "plain": false])
        marked.hasUnreadReply = false
        try store.save(conversation: marked)
        XCTAssertEqual(try read(), ["marked": false, "plain": false])
        marked.hasUnreadReply = true
        try store.save(conversation: marked)
        XCTAssertEqual(try read(), ["marked": true, "plain": false])
    }

    /// A store the build before the mark wrote opens in this one with nothing
    /// unread. One this build wrote, with a conversation marked, opens under
    /// the earlier schema with the conversation and its messages kept.
    @MainActor
    func testAStoreOpensAcrossTheUnreadChangeInBothDirections() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)

        let older = scratch.support.appending(path: "older.store")
        do {
            // Held: a context whose container has gone traps on its next use.
            let written = try container(BeforeUnread.schema, at: older)
            let context = written.mainContext
            let conversation = BeforeUnread.ConversationRecord(id: UUID(), title: "kept", createdAt: stamp)
            context.insert(conversation)
            let message = BeforeUnread.MessageRecord(
                id: UUID(), role: "assistant", content: "hello", createdAt: stamp, order: 0)
            message.conversation = conversation
            context.insert(message)
            try context.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let conversation = try XCTUnwrap(opened.loadConversations().first)
        XCTAssertEqual(conversation.title, "kept")
        XCTAssertEqual(conversation.messages.map(\.content), ["hello"])
        XCTAssertFalse(conversation.hasUnreadReply)

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            var marked = Conversation(title: "marked", createdAt: stamp, updatedAt: stamp, hasUnreadReply: true)
            marked.messages = [Message(role: .assistant, content: "done", createdAt: stamp)]
            try store.save(conversation: marked)
        }
        let earlier = try container(BeforeUnread.schema, at: newer)
        let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeUnread.ConversationRecord>())
        XCTAssertEqual(rows.map(\.title), ["marked"])
        XCTAssertEqual(rows.first?.messages.map(\.content), ["done"])
    }
}
