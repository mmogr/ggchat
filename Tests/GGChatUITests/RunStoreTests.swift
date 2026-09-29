import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before runs declared them, for opening a store
/// across the change in both directions.
enum EarlierBuild {
    @Model
    final class ProviderRecord {
        @Attribute(.unique) var uuid: UUID
        var name: String
        var kindData: Data
        var defaultModel: String?
        var createdAt: Date
        var lastHeard: Date?

        init(id: UUID, name: String, kindData: Data, createdAt: Date) {
            self.uuid = id
            self.name = name
            self.kindData = kindData
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

        init(id: UUID, createdAt: Date) {
            self.uuid = id
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

        init(id: UUID, role: String, content: String, isPartial: Bool, createdAt: Date, order: Int) {
            self.uuid = id
            self.role = role
            self.content = content
            self.isPartial = isPartial
            self.createdAt = createdAt
            self.order = order
        }
    }

    static let schema = Schema([ProviderRecord.self, ConversationRecord.self, MessageRecord.self])
}

/// A message's run id and cursor are kept with it, and a store opens across
/// the change that added them.
final class RunStoreTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The id and cursor are read back as written, and cleared as written.
    @MainActor
    func testARunsIDAndCursorAreKeptWithItsMessage() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        var conversation = Conversation(createdAt: stamp, updatedAt: stamp)
        conversation.messages = [
            Message(role: .user, content: "hi", createdAt: stamp),
            Message(role: .assistant, content: "hal", isPartial: true, createdAt: stamp, runID: "run-1", runCursor: 7),
        ]
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation])
        conversation.messages[1].runCursor = 4_000_000_000
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations().first?.messages[1].runCursor, 4_000_000_000)
        conversation.messages[1].runID = nil
        conversation.messages[1].runCursor = nil
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation])
    }

    /// A store the earlier build wrote opens in this one, every message
    /// reading no run. One this build wrote opens in the earlier build too,
    /// with the reply kept and its run forgotten, so that build shows the
    /// partial with Continue.
    @MainActor
    func testAStoreOpensAcrossTheChangeInBothDirections() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)

        let older = scratch.support.appending(path: "older.store")
        do {
            // Held: a context whose container has gone traps on its next use.
            let written = try container(EarlierBuild.schema, at: older)
            let context = written.mainContext
            let kind = try JSONEncoder().encode(ProviderConfig.Kind.pipe(ticketDigest: "abc"))
            context.insert(EarlierBuild.ProviderRecord(id: UUID(), name: "home", kindData: kind, createdAt: stamp))
            let conversation = EarlierBuild.ConversationRecord(id: UUID(), createdAt: stamp)
            context.insert(conversation)
            let message = EarlierBuild.MessageRecord(
                id: UUID(), role: "assistant", content: "kept", isPartial: true, createdAt: stamp, order: 0)
            message.conversation = conversation
            context.insert(message)
            try context.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let message = try XCTUnwrap(opened.loadConversations().first?.messages.first)
        XCTAssertEqual(try opened.loadProviders().map(\.name), ["home"])
        XCTAssertEqual(message.content, "kept")
        XCTAssertNil(message.runID)
        XCTAssertNil(message.runCursor)

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            var conversation = Conversation(createdAt: stamp, updatedAt: stamp)
            conversation.messages = [
                Message(role: .assistant, content: "half", isPartial: true, createdAt: stamp, runID: "r", runCursor: 3)
            ]
            try store.save(conversation: conversation)
        }
        let earlier = try container(EarlierBuild.schema, at: newer)
        let rows = try earlier.mainContext.fetch(FetchDescriptor<EarlierBuild.MessageRecord>())
        XCTAssertEqual(rows.map(\.content), ["half"])
        XCTAssertEqual(rows.map(\.isPartial), [true])
    }
}
