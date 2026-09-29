import GGChatCore
import XCTest

@testable import GGChatUI

/// The list says which conversations have a reply still being written, and
/// which have one that ended while nobody had them open.
final class AppModelListMarkTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    /// Sends in the open conversation and holds the reply after three frames.
    @MainActor
    private func sendAndHold(_ model: AppModel, _ hub: FakeRunHub) async throws -> (Conversation, Task<Void, Never>) {
        hub.with { $0.holdAt = 3 }
        let conversation = try XCTUnwrap(model.selectedConversation)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("three frames") { model.liveReply?.cursor == 3 }
        return (conversation, task)
    }

    /// Comes back to a hub that no longer holds, and waits for every reply.
    @MainActor
    private func comeBack(_ model: AppModel, _ hub: FakeRunHub) async throws {
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("every reply to end") {
            model.liveReply == nil && !model.conversations.contains { $0.messages.contains(where: \.isBeingWritten) }
        }
    }

    @MainActor
    private func mark(_ model: AppModel, _ id: UUID) throws -> ConversationMark? {
        model.mark(for: try XCTUnwrap(model.conversations.first { $0.id == id }))
    }

    /// A reply streaming in front is writing, and so is one the hub goes on
    /// writing after the background, whichever conversation is open.
    @MainActor
    func testAReplyStillBeingWrittenIsWritingInTheList() async throws {
        let hub = hub()
        let (model, _) = try await Runs.makeModel(behind: hub)
        let (asked, task) = try await sendAndHold(model, hub)
        XCTAssertEqual(try mark(model, asked.id), .writing)
        let other = model.newConversation()
        XCTAssertEqual(try mark(model, asked.id), .writing)
        XCTAssertNil(try mark(model, other.id))
        await model.scene(.background).value
        await task.value
        XCTAssertNil(model.liveReply)
        XCTAssertEqual(try mark(model, asked.id), .writing, "a run the hub is still writing is not marked")
    }

    /// A reply that finishes, fails or is given up while another conversation
    /// is open is unread, in memory and in the store, until its conversation
    /// is opened; opening it clears both.
    @MainActor
    func testAReplyThatEndsWhileAnotherIsOpenIsUnreadUntilOpened() async throws {
        for ending in ["finished", "failed", "given up"] {
            let hub = hub()
            let store = InMemoryStore()
            let (model, _) = try await Runs.makeModel(behind: hub, store: store)
            let (asked, task) = try await sendAndHold(model, hub)
            let other = model.newConversation()
            await model.scene(.background).value
            await task.value
            XCTAssertFalse(try XCTUnwrap(store.loadConversations().first { $0.id == asked.id }).hasUnreadReply)
            switch ending {
            case "failed": hub.with { $0.ending = .failed }
            case "given up": hub.with { $0.forgotten = true }
            default: break
            }
            try await comeBack(model, hub)
            XCTAssertEqual(try mark(model, asked.id), .unread, "a reply that \(ending) was not marked")
            XCTAssertNil(try mark(model, other.id), ending)
            let kept = try XCTUnwrap(store.loadConversations().first { $0.id == asked.id })
            XCTAssertTrue(kept.hasUnreadReply, "the mark of a reply that \(ending) was not kept")

            model.selectedConversationID = asked.id
            XCTAssertNil(try mark(model, asked.id), "opening a reply that \(ending) did not clear it")
            XCTAssertFalse(try XCTUnwrap(store.loadConversations().first { $0.id == asked.id }).hasUnreadReply)
        }
    }

    /// A reply that finishes while its conversation is open is never unread:
    /// neither one read in front, nor one read on after coming back.
    @MainActor
    func testAReplyThatEndsWhileItsConversationIsOpenIsNeverUnread() async throws {
        let hub = hub()
        let store = InMemoryStore()
        let (model, _) = try await Runs.makeModel(behind: hub, store: store)
        let asked = try XCTUnwrap(model.selectedConversation)
        try await XCTUnwrap(model.send("one")).value
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertNil(try mark(model, asked.id))

        let (_, task) = try await sendAndHold(model, hub)
        await model.scene(.background).value
        await task.value
        try await comeBack(model, hub)
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertFalse(try Runs.last(model).isPartial)
        XCTAssertNil(try mark(model, asked.id))
        XCTAssertEqual(try store.loadConversations().map(\.hasUnreadReply), [false])
    }

    /// The marks leave the list's order as it was: opening a conversation to
    /// clear one changes neither its place nor when it was last changed, so a
    /// relaunch lists the conversations as before.
    @MainActor
    func testTheMarksLeaveTheOrderAsItWas() throws {
        let store = InMemoryStore()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, title) in ["newest", "middle", "oldest"].enumerated() {
            let stamp = day.addingTimeInterval(-Double(index) * 60)
            let conversation = Conversation(
                title: title, createdAt: stamp, updatedAt: stamp, hasUnreadReply: title != "newest")
            try store.save(conversation: conversation)
        }
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: LoopbackProviderRegistry())
        model.load()
        XCTAssertEqual(model.conversations.map(\.title), ["newest", "middle", "oldest"])
        XCTAssertEqual(model.conversations.map { model.mark(for: $0) }, [nil, .unread, .unread])
        let before = model.conversations.map(\.updatedAt)
        model.selectedConversationID = model.conversations[2].id
        XCTAssertEqual(model.conversations.map { model.mark(for: $0) }, [nil, .unread, nil])
        XCTAssertEqual(model.conversations.map(\.title), ["newest", "middle", "oldest"])
        XCTAssertEqual(model.conversations.map(\.updatedAt), before)
        let reloaded = try store.loadConversations().sorted { $0.updatedAt > $1.updatedAt }
        XCTAssertEqual(reloaded.map(\.title), ["newest", "middle", "oldest"])
        XCTAssertEqual(reloaded.map(\.hasUnreadReply), [false, true, false])
    }

    /// Each mark has a word of its own and a label VoiceOver reads, so
    /// neither is told by colour alone.
    @MainActor
    func testEachMarkHasAWordAndALabel() {
        XCTAssertEqual(ConversationMark.writing.word, "Writing")
        XCTAssertEqual(ConversationMark.unread.word, "New")
        XCTAssertEqual(ConversationMark.writing.accessibilityLabel, "Reply still being written")
        XCTAssertEqual(ConversationMark.unread.accessibilityLabel, "Unread reply")
    }
}
