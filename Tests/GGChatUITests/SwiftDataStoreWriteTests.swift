import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// Saving a conversation marks only what changed (#139). A `@Model` setter
/// marks its row changed even for the value it already holds, so these look
/// at what `write(_:)` marked before anything is saved.
final class SwiftDataStoreWriteTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    private let refused = Failure(
        .server(status: 401, code: "invalid_api_key", message: "invalid or missing bearer token"))

    /// A conversation with something in every field a save writes.
    private func conversation() -> Conversation {
        var conversation = Conversation(
            title: "t", providerID: UUID(), model: "m", systemPrompt: "Answer in French.", createdAt: stamp,
            updatedAt: stamp, hasUnreadReply: true)
        conversation.messages = [
            Message(role: .user, content: "anyone?", failure: refused, createdAt: stamp),
            Message(role: .user, content: "go on", createdAt: stamp),
            Message(
                role: .assistant, content: "half", reasoning: "thinking", isPartial: true, createdAt: stamp,
                runID: "run-1", runCursor: 7),
        ]
        return conversation
    }

    /// The rows `write(_:)` has marked changed: the conversation's by its
    /// title, each message's by its content.
    @MainActor
    private func changed(_ store: SwiftDataStore) -> [String] {
        store.context.changedModelsArray.compactMap { model in
            if let row = model as? ConversationRecord { return "conversation \(row.title)" }
            if let row = model as? MessageRecord { return "message \(row.content)" }
            return "something else"
        }
        .sorted()
    }

    @MainActor
    private func row(_ id: UUID, in store: SwiftDataStore) throws -> MessageRecord {
        let rows = try store.context.fetch(FetchDescriptor<MessageRecord>())
        return try XCTUnwrap(rows.first { $0.uuid == id })
    }

    /// Saved once, then written again unchanged, as read back and as held:
    /// no row is marked, so the save after it writes nothing.
    @MainActor
    func testWritingAnUnchangedConversationChangesNoRow() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let conversation = conversation()
        try store.save(conversation: conversation)
        let readBack = try XCTUnwrap(store.loadConversations().first)
        XCTAssertEqual(readBack, conversation)

        try store.write(readBack)
        XCTAssertEqual(changed(store), [], "a write marked rows nothing had changed")
        try store.write(conversation)
        XCTAssertEqual(changed(store), [], "a write marked rows nothing had changed")
        XCTAssertFalse(store.context.hasChanges)
    }

    /// One message edited changes that row alone; the unread mark cleared, as
    /// opening the conversation clears it, changes the conversation's alone;
    /// a run's cursor moving on is kept; and every other field a save
    /// assigns, the order of two messages with them, reaches the store.
    @MainActor
    func testChangingOneThingChangesOnlyItsRow() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        var conversation = conversation()
        try store.save(conversation: conversation)

        conversation.messages[2].content = "half and more"
        try store.write(conversation)
        XCTAssertEqual(changed(store), ["message half and more"])
        try store.context.save()

        conversation.hasUnreadReply = false
        try store.write(conversation)
        XCTAssertEqual(changed(store), ["conversation t"])
        try store.context.save()

        conversation.messages[2].runCursor = 9
        try store.write(conversation)
        XCTAssertEqual(changed(store), ["message half and more"])
        try store.context.save()

        conversation.title = "u"
        conversation.providerID = UUID()
        conversation.model = "n"
        conversation.systemPrompt = "Answer in German."
        conversation.updatedAt = stamp.addingTimeInterval(60)
        conversation.messages.swapAt(0, 1)
        conversation.messages[2].reasoning = "thinking more"
        conversation.messages[2].isPartial = false
        conversation.messages[2].runID = nil
        conversation.messages[2].runCursor = nil
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations(), [conversation], "a change did not reach the store")
    }

    /// A failure is not encoded again unless it changed: the same failure in
    /// other bytes is left in those bytes, and a new one replaces it.
    @MainActor
    func testAFailureIsWrittenOnlyWhenItChanged() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        var conversation = conversation()
        try store.save(conversation: conversation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let otherBytes = try encoder.encode(refused)
        let question = try row(conversation.messages[0].id, in: store)
        XCTAssertNotEqual(question.failureData, otherBytes, "the bytes are not other bytes")
        question.failureData = otherBytes
        try store.context.save()

        try store.write(conversation)
        XCTAssertEqual(changed(store), [], "a failure that did not change was encoded again")
        XCTAssertEqual(question.failureData, otherBytes)

        let dropped = Failure(.transport("the network went away"))
        conversation.messages[0].failure = dropped
        try store.save(conversation: conversation)
        XCTAssertEqual(try store.loadConversations().first?.messages[0].failure, dropped)

        conversation.messages[0].failure = nil
        try store.save(conversation: conversation)
        XCTAssertNil(question.failureData, "a cleared failure was kept")
    }
}
