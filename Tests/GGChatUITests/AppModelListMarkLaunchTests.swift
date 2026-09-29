import GGChatCore
import XCTest

@testable import GGChatUI

/// Selecting is not reading: a launch keeps every mark, a reply that ends
/// with no chat on screen is unread, and one the person stopped never is.
final class AppModelListMarkLaunchTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    @MainActor
    private func conversation(_ model: AppModel, _ id: UUID) throws -> Conversation {
        try XCTUnwrap(model.conversations.first { $0.id == id })
    }

    @MainActor
    private func stored(_ store: InMemoryStore, _ id: UUID) throws -> Conversation {
        try XCTUnwrap(store.loadConversations().first { $0.id == id })
    }

    /// Sends in the open conversation, with its chat on screen, and holds the
    /// reply after three frames.
    @MainActor
    private func sendAndHold(_ model: AppModel, _ hub: FakeRunHub) async throws -> (UUID, Task<Void, Never>) {
        hub.with { $0.holdAt = 3 }
        let asked = try XCTUnwrap(model.selectedConversationID)
        model.chatAppeared(asked)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("three frames") { model.liveReply?.cursor == 3 }
        return (asked, task)
    }

    /// A launch restores its selection and clears nothing. A chat shown with
    /// the app away clears nothing either; coming back to it in front does.
    @MainActor
    func testALaunchKeepsEveryMarkUntilItsChatIsShownInFront() async throws {
        let store = InMemoryStore()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let newest = Conversation(title: "newest", createdAt: day, updatedAt: day, hasUnreadReply: true)
        let older = Conversation(
            title: "older", createdAt: day - 60, updatedAt: day - 60, hasUnreadReply: true)
        try store.save(conversation: older)
        try store.save(conversation: newest)
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: LoopbackProviderRegistry())
        model.load()
        XCTAssertEqual(model.selectedConversationID, newest.id)
        XCTAssertEqual(model.conversations.map { model.mark(for: $0) }, [.unread, .unread])
        XCTAssertEqual(try [stored(store, newest.id), stored(store, older.id)].map(\.hasUnreadReply), [true, true])

        model.chatAppeared(newest.id)
        XCTAssertFalse(try conversation(model, newest.id).hasUnreadReply, "showing the chat did not clear it")
        XCTAssertFalse(try stored(store, newest.id).hasUnreadReply)
        XCTAssertTrue(try conversation(model, older.id).hasUnreadReply)

        await model.scene(.background).value
        model.selectedConversationID = older.id
        model.chatAppeared(older.id)
        XCTAssertTrue(try conversation(model, older.id).hasUnreadReply, "a chat shown while away was read")
        await model.scene(.foreground).value
        XCTAssertFalse(try conversation(model, older.id).hasUnreadReply, "coming back to the chat did not read it")
        XCTAssertFalse(try stored(store, older.id).hasUnreadReply)
    }

    /// A launch restores the conversation a reply was still being written in,
    /// on a phone that shows the list. The reply read on at launch ends with
    /// no chat on screen, so it is unread, and kept so.
    @MainActor
    func testAReplyReadOnAtLaunchInTheRestoredConversationIsUnread() async throws {
        let hub = hub()
        let store = InMemoryStore()
        let secrets = InMemorySecrets()
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(Runs.ticket)), defaultModel: "mock-27b")
        try store.save(provider: config)
        try secrets.setSecret(Runs.ticket, .ticket, for: config.id)
        try secrets.setSecret("secret-token", .token, for: config.id)
        let kept = Conversation(
            providerID: config.id,
            messages: [
                Message(role: .user, content: "go", createdAt: .distantPast),
                Message(
                    role: .assistant, content: "", isPartial: true, createdAt: .distantPast, runID: "r", runCursor: 3),
            ], createdAt: .distantPast, updatedAt: .distantPast)
        try store.save(conversation: kept)
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: store, secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: hub, registry: registry),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "marks.\(UUID().uuidString)")!))

        model.load()

        XCTAssertEqual(model.selectedConversationID, kept.id)
        try await Runs.until("the reply to be read on") {
            model.liveReply == nil && model.selectedConversation?.messages.last?.runID == nil
        }
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertEqual(model.mark(for: try conversation(model, kept.id)), .unread)
        XCTAssertTrue(try stored(store, kept.id).hasUnreadReply)
    }

    /// Going Back to the list on a phone clears the selection, and the chat
    /// shown before it is no longer being read: a reply that ends then is
    /// unread.
    @MainActor
    func testAReplyThatEndsWithNoChatShownIsUnread() async throws {
        let hub = hub()
        let (model, _) = try await Runs.makeModel(behind: hub)
        let (asked, task) = try await sendAndHold(model, hub)
        model.selectedConversationID = nil
        await model.scene(.background).value
        await task.value
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply to end") {
            model.liveReply == nil && (try? self.conversation(model, asked).messages.last?.isBeingWritten) == false
        }
        XCTAssertEqual(try conversation(model, asked).messages.last?.content, Runs.text)
        XCTAssertEqual(model.mark(for: try conversation(model, asked)), .unread)
    }

    /// On iOS 27 a phone that opens a chat after going Back, or starts one
    /// from the list's toolbar, tells the chat it disappeared a millisecond
    /// after it appeared, while it stays on screen. The model is told only
    /// the appear, so a reply that then ends in front of the person is read.
    @MainActor
    func testAChatOpenedAfterGoingBackIsReadWhateverFollowsItsAppear() async throws {
        let hub = hub()
        let (model, _) = try await Runs.makeModel(behind: hub)
        let first = try XCTUnwrap(model.selectedConversationID)
        model.chatAppeared(first)
        model.selectedConversationID = nil
        let started = model.newConversation()
        let (asked, task) = try await sendAndHold(model, hub)
        XCTAssertEqual(asked, started.id)
        await model.scene(.background).value
        await task.value
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply to end") {
            model.liveReply == nil && (try? self.conversation(model, asked).messages.last?.isBeingWritten) == false
        }
        XCTAssertEqual(try conversation(model, asked).messages.last?.content, Runs.text)
        XCTAssertNil(model.mark(for: try conversation(model, asked)), "a reply watched after going Back was marked")

        model.selectedConversationID = nil
        model.selectedConversationID = first
        model.chatAppeared(first)
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(try conversation(model, first).messages.last?.content, Runs.text)
        XCTAssertNil(model.mark(for: try conversation(model, first)), "a reply watched after reopening was marked")
    }

    /// A reply the person stopped is never unread, even when another
    /// conversation is open by the time it ends: one read in front, and one
    /// the hub was writing away from here.
    @MainActor
    func testAReplyThePersonStoppedIsNeverUnread() async throws {
        let hub = hub()
        let (model, _) = try await Runs.makeModel(behind: hub)
        var (asked, task) = try await sendAndHold(model, hub)
        model.stop()
        model.chatAppeared(model.newConversation().id)
        await task.value
        XCTAssertEqual(try conversation(model, asked).messages.last?.isPartial, true)
        XCTAssertNil(model.mark(for: try conversation(model, asked)), "a reply stopped in front was marked")

        model.selectedConversationID = asked
        (asked, task) = try await sendAndHold(model, hub)
        await model.scene(.background).value
        await task.value
        await model.scene(.foreground).value
        model.chatAppeared(model.newConversation().id)
        let writing = try XCTUnwrap(conversation(model, asked).messages.last { $0.isBeingWritten })
        model.stopWriting(writing.id)
        try await Runs.until("the reply to be let go") {
            (try? self.conversation(model, asked).messages.last?.isBeingWritten) == false
        }
        XCTAssertNil(model.mark(for: try conversation(model, asked)), "a reply stopped away from here was marked")
    }
}
