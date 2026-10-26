import GGChatCore
import XCTest

@testable import GGChatUI

/// The wrench's "!": shown while the paired Mac offers a server the
/// conversation has never shown, and cleared by a change made from its
/// menu, or by its rows coming on screen in the Duo's panel. A SwiftUI menu
/// says nothing of being opened, so opening it alone does not clear it.
@MainActor
final class ToolsSeenTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private let tavily = OfferedServer(id: 3, name: "tavily")
    private let files = OfferedServer(id: 9, name: "fs")

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    private func menu(_ model: AppModel) throws -> ToolsMenu {
        model.toolsMenu(for: try XCTUnwrap(model.selectedConversation))
    }

    /// A new conversation on a Mac that offers servers is badged, says so in
    /// its name, has its rows marked new, and picks none.
    func testANewChatIsBadgedAndPicksNone() async throws {
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily)
        let menu = try menu(model)
        XCTAssertTrue(menu.badged)
        XCTAssertEqual(menu.label, "Tools, none picked, new tools available")
        XCTAssertEqual(menu.rows.map(\.isNew), [true])
        XCTAssertEqual(menu.running, [])
    }

    /// A change made from the menu shows every server offered in the same
    /// write, whichever row it was: the badge and the "New" marks go, the
    /// name loses its words for them, and the other server stays unpicked.
    func testAChangeFromTheMenuClearsTheBadge() async throws {
        let both = Drawing(available: true, mcpServers: [tavily, files])
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: both)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.setServer(3, picked: true, for: id)
        let menu = try menu(model)
        XCTAssertFalse(menu.badged)
        XCTAssertEqual(menu.label, "Tools, 1 server")
        XCTAssertEqual(menu.rows.map(\.isNew), [false, false])
        XCTAssertEqual(model.selectedConversation?.toolChoice, ToolChoice(picked: [3], seen: [3, 9]))
    }

    /// The panel's rows coming on screen show the servers once: shown again,
    /// with nothing new, a store that refuses every write is not asked. The
    /// date is left alone.
    func testMarkingSeenTwiceWritesOnce() async throws {
        let store = RefusingStore()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily, store: store)
        let conversation = try XCTUnwrap(model.selectedConversation)
        model.markToolsSeen(for: conversation.id)
        XCTAssertFalse(try menu(model).badged)
        XCTAssertEqual(model.selectedConversation?.toolChoice, ToolChoice(seen: [3]))
        XCTAssertEqual(model.selectedConversation?.updatedAt, conversation.updatedAt)
        store.refusesConversationSaves = true
        model.markToolsSeen(for: conversation.id)
        XCTAssertNil(model.lastError, "showing the servers again wrote the conversation")
    }

    /// A server the Mac opens later badges every conversation on it, each
    /// leaving it unpicked, while what each picked stays picked.
    func testAServerTheMacOpensLaterIsBadgedInEveryChatAndUnpicked() async throws {
        let (model, config) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily)
        let first = try XCTUnwrap(model.selectedConversationID)
        model.setServer(3, picked: true, for: first)
        let second = model.newConversation()
        model.markToolsSeen(for: second.id)
        model.drawings[config.id] = Drawing(available: true, mcpServers: [tavily, files])
        for id in [first, second.id] {
            let conversation = try XCTUnwrap(model.conversations.first { $0.id == id })
            let menu = model.toolsMenu(for: conversation)
            XCTAssertTrue(menu.badged, "a conversation was not badged for the server opened later")
            XCTAssertEqual(menu.rows.map(\.isNew), [false, true])
            XCTAssertEqual(menu.rows.map(\.picked), [id == first, false])
        }
    }

    /// A branch copies what its conversation has shown, so it is not badged
    /// for a server its source showed, and is for one neither has.
    func testABranchIsNotBadgedForWhatItsSourceSaw() async throws {
        let (model, config) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily)
        let source = Conversation(
            providerID: config.id,
            messages: [
                Message(role: .user, content: "Plan a trip", createdAt: .distantPast),
                Message(role: .assistant, content: "Day 1", createdAt: .distantPast),
            ], createdAt: .distantPast, updatedAt: .distantPast, toolChoice: ToolChoice(seen: [3]))
        let branch = try source.applying(.branch(messageID: source.messages[1].id), busy: false, now: .distantPast)
        XCTAssertTrue(
            model.toolsMenu(for: Conversation(providerID: config.id, createdAt: .now, updatedAt: .now)).badged)
        XCTAssertFalse(model.toolsMenu(for: branch.conversation).badged)
        model.drawings[config.id] = Drawing(available: true, mcpServers: [tavily, files])
        XCTAssertEqual(model.toolsMenu(for: branch.conversation).rows.map(\.isNew), [false, true])
    }
}
