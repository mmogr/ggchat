import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A chat a later build wrote a turn into that this one cannot read is left
/// out of the list whole, kept in the store untouched, and counted for the
/// window to say so.
@MainActor
final class StoreUnknownRoleTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// A store holding one chat this build wrote and one, `laterID`, with a
    /// `tool` turn, a role this build does not know.
    private struct Made {
        let store: SwiftDataStore
        let readable: Conversation
        let laterID: UUID
    }

    private func makeStore() throws -> Made {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        var readable = Conversation(title: "mine", providerID: UUID(), model: "m", createdAt: stamp, updatedAt: stamp)
        readable.messages = [Message(role: .user, content: "hi", createdAt: stamp)]
        try store.save(conversation: readable)

        let laterID = UUID()
        let later = ConversationRecord(
            id: laterID, title: "later", providerID: nil, model: "m", createdAt: stamp, updatedAt: stamp)
        store.context.insert(later)
        for (order, role) in ["user", "tool"].enumerated() {
            let turn = MessageRecord(
                id: UUID(), role: role, content: "turn \(order)", reasoning: nil, isPartial: false, createdAt: stamp,
                order: order)
            turn.conversation = later
            store.context.insert(turn)
        }
        try store.context.save()
        return Made(store: store, readable: readable, laterID: laterID)
    }

    private func turns(of id: UUID, in store: SwiftDataStore) throws -> [String] {
        try store.context.fetch(FetchDescriptor<MessageRecord>())
            .filter { $0.conversation?.uuid == id }
            .sorted { $0.order < $1.order }
            .map(\.role)
    }

    /// Read as a question, the `tool` turn would be shown and sent as one;
    /// loaded without it, the chat would lose it at its next save. Left out,
    /// it is still in the store after another chat is saved and loaded again.
    func testAChatHoldingATurnThisBuildCannotReadIsLeftOutAndKept() throws {
        let made = try makeStore()
        let (store, laterID) = (made.store, made.laterID)
        var readable = made.readable

        XCTAssertEqual(try store.loadConversations(), [readable])
        XCTAssertEqual(store.hiddenChats, 1)

        readable.messages.append(Message(role: .assistant, content: "hello", createdAt: stamp))
        try store.save(conversation: readable)
        XCTAssertEqual(try store.loadConversations(), [readable])
        XCTAssertEqual(store.hiddenChats, 1)
        XCTAssertEqual(try turns(of: laterID, in: store), ["user", "tool"], "the hidden chat was written over")
    }

    /// The model keeps the count the store gave it, and the window says it
    /// between the red line and the older store's.
    func testTheWindowSaysHowManyChatsWereLeftOut() throws {
        let made = try makeStore()
        let (store, readable) = (made.store, made.readable)
        let model = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink(), now: { .distantPast })
        model.load()
        XCTAssertEqual(model.conversations.map(\.id), [readable.id])
        XCTAssertEqual(model.hiddenChats, 1)

        let nothing = ShownStoreNotice(nil)
        XCTAssertEqual(nothing.lines(hidingChats: 0), [])
        XCTAssertEqual(
            nothing.lines(hidingChats: model.hiddenChats).map(\.sentence),
            ["1 chat was saved by a newer version of ggchat and is not shown. It has not been deleted."])
        XCTAssertEqual(
            StoreNotice.Line.hiddenChats(2).sentence,
            "2 chats were saved by a newer version of ggchat and are not shown. They have not been deleted.")
        let both = ShownStoreNotice(StoreNotice(keptInMemory: true, olderStoreLeftBehind: true))
        XCTAssertEqual(both.lines(hidingChats: 2), [.keptInMemory, .hiddenChats(2), .olderStore])
    }
}
