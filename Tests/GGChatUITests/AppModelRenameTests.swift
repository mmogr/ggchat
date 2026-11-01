import GGChatCore
import XCTest

@testable import GGChatUI

/// Renaming a conversation kept on this device: the name is kept in the
/// store, over the title its first question gives it, until it is cleared.
@MainActor
final class AppModelRenameTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_700_000_600)

    /// A model holding two conversations, the trip one older, so it is
    /// second in the list.
    private func makeModel() throws -> (AppModel, UUID) {
        let store = InMemoryStore()
        let trip = Conversation(
            messages: [Message(role: .user, content: "Plan a trip to Kyoto", createdAt: older)],
            createdAt: older, updatedAt: older)
        try store.save(conversation: trip)
        try store.save(conversation: Conversation(createdAt: newer, updatedAt: newer))
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: LoopbackProviderRegistry())
        model.load()
        return (model, trip.id)
    }

    private func stored(_ id: UUID, in model: AppModel) throws -> Conversation {
        try XCTUnwrap(model.store.loadConversations().first { $0.id == id })
    }

    /// The name, trimmed, is what the list calls the chat and what the store
    /// keeps; the chat keeps its place and its `updatedAt`.
    func testARenamedChatIsCalledByItsNameAndKeepsItsPlace() throws {
        let (model, trip) = try makeModel()
        let order = model.conversations.map(\.id)
        model.renameConversation(trip, to: "  Kyoto in spring \n")
        XCTAssertEqual(model.conversations.first { $0.id == trip }?.displayTitle, "Kyoto in spring")
        XCTAssertEqual(try stored(trip, in: model).title, "Kyoto in spring")
        XCTAssertEqual(try stored(trip, in: model).updatedAt, older, "a rename moved the chat in time")
        XCTAssertEqual(model.conversations.map(\.id), order, "a rename moved the chat in the list")
    }

    /// A name cleared gives the chat its first question's title back.
    func testAClearedNameGivesBackTheFirstQuestionsTitle() throws {
        let (model, trip) = try makeModel()
        model.renameConversation(trip, to: "Kyoto in spring")
        model.renameConversation(trip, to: "   ")
        XCTAssertEqual(try stored(trip, in: model).title, "")
        XCTAssertEqual(try stored(trip, in: model).displayTitle, "Plan a trip to Kyoto")
    }

    /// The title already shown, confirmed as offered, is not kept as a name,
    /// so the chat goes on taking its title from its first question; and a
    /// chat this device does not have is not made.
    func testTheTitleAlreadyShownAndAChatNotHereChangeNothing() throws {
        let (model, trip) = try makeModel()
        model.renameConversation(trip, to: "Plan a trip to Kyoto")
        XCTAssertEqual(try stored(trip, in: model).title, "")
        let before = try model.store.loadConversations()
        model.renameConversation(UUID(), to: "Nowhere")
        XCTAssertEqual(try model.store.loadConversations(), before)
    }
}
