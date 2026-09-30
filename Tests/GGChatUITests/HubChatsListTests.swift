import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A paired Mac's chats in the list: listed live when its pipe comes up,
/// opened read only, and never written to this phone's store.
@MainActor
final class HubChatsListTests: XCTestCase {
    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    func testTheMacsChatsAreListedWhenItsPipeComesUp() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub)
        try await until("the list") { model.hubChats[config.id] == FakeChatsHub.summaries }
        XCTAssertEqual(model.hubProviders.map(\.id), [config.id])
        XCTAssertNil(model.hubLine(for: config.id))
        XCTAssertEqual(model.mark(for: FakeChatsHub.summaries[0]), .writing, "a chat with a live run")
        XCTAssertNil(model.mark(for: FakeChatsHub.summaries[1]))
    }

    /// A server added by address has no section, and its chats are never
    /// asked for: gglib reads them only to a device through its tunnel.
    func testOnlyAPairedMacHasASection() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub, direct: true)
        await model.refreshHubChats()
        await model.listHubChats(config.id)
        XCTAssertEqual(model.hubProviders, [])
        XCTAssertNil(model.hubChats[config.id])
        XCTAssertEqual(hub.with(\.lists), 0)
    }

    /// Opening a chat reads its rows and draws the turns with words in them,
    /// and Back drops it. The store holds what it held before: no
    /// conversation and no message row came from the Mac.
    func testOpeningAChatReadsItsRowsAndKeepsNothing() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let hub = FakeChatsHub()
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub, store: store)
        var local = try XCTUnwrap(model.selectedConversation)
        local.messages = [Message(role: .user, content: "kept here", createdAt: local.createdAt)]
        model.update(local)
        let before = try store.loadConversations()
        let rowsBefore = try store.context.fetchCount(FetchDescriptor<MessageRecord>())

        try await until("the list") { model.hubChats[config.id] != nil }
        model.selection = .hub(providerID: config.id, chatID: 12)
        XCTAssertNil(model.selectedConversationID, "a Mac's chat is not a local selection")
        try await until("the rows") { model.openedHubChat?.state != .reading }
        let open = try XCTUnwrap(model.openedHubChat)
        XCTAssertEqual(open.title, "Why the build broke")
        guard case .read(let rows) = open.state else { return XCTFail("not read: \(open.state)") }
        XCTAssertEqual(rows.map(\.content), ["Why did the build break?", "A dependency moved."])
        XCTAssertEqual(rows.map(\.role), [.user, .assistant])
        XCTAssertEqual(hub.with(\.opens), [12])

        XCTAssertEqual(try store.loadConversations(), before)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<MessageRecord>()), rowsBefore)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ConversationRecord>()), 1)
        XCTAssertEqual(model.conversations.map(\.id), [local.id])

        model.selection = nil
        XCTAssertNil(model.openedHubChat, "Back kept the chat")
        XCTAssertNil(model.selection)
    }

    /// Choosing a conversation on this phone drops the Mac's chat, and
    /// choosing the Mac's drops the local selection.
    func testTheTwoKindsOfSelectionDropEachOther() async throws {
        let (model, config) = try await AppModelRunTests.makeModel(behind: FakeChatsHub())
        let local = try XCTUnwrap(model.selectedConversationID)
        model.selection = .hub(providerID: config.id, chatID: 9)
        XCTAssertEqual(model.selection, .hub(providerID: config.id, chatID: 9))
        try await until("the answer") { model.openedHubChat?.state != .reading }
        XCTAssertEqual(model.openedHubChat?.state, .unavailable("home no longer has this chat."))
        model.selection = .local(local)
        XCTAssertNil(model.openedHubChat)
        XCTAssertEqual(model.selectedConversationID, local)
    }

    /// A Mac that reads its chats only to a device through its tunnel says so
    /// under its section, and when one of them is opened.
    func testAMacThatDoesNotShareItsChatsSaysSo() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.list = .failure(.notShared) }
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub)
        try await until("the refusal") { model.hubLine(for: config.id) != nil }
        XCTAssertEqual(model.hubLine(for: config.id), "home does not share its chats with this phone.")
        XCTAssertEqual(model.hubChats[config.id], nil)
    }

    /// The launch dials every paired Mac quietly: one this device has no
    /// ticket for raises no alert, as any other quiet dial that fails.
    func testAQuietDialWithNothingToDialWithRaisesNoAlert() async throws {
        let (model, _) = try await AppModelRunTests.makeModel(behind: FakeChatsHub())
        let orphan = ProviderConfig(name: "orphan", kind: .pipe(ticketDigest: "x"))
        try model.addProvider(orphan, credentials: [:])
        await model.refreshHubChats()
        XCTAssertNil(model.lastError)
        XCTAssertNil(model.pipeSession(for: orphan.id))
    }

    /// A pull lists again, and dials a pipe that is down first.
    func testAPullDialsAPipeThatIsDownAndListsAgain() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub)
        try await until("the first list") { model.hubChats[config.id] != nil && model.hubListing.isEmpty }
        await model.disconnectPipe(for: config.id, leaving: .closed)
        let lists = hub.with(\.lists)
        hub.with { $0.list = .success(HubChatList(chats: [FakeChatsHub.summaries[1]])) }
        await model.refreshHubChats()
        try await until("the second list") { model.hubChats[config.id] == [FakeChatsHub.summaries[1]] }
        XCTAssertGreaterThan(hub.with(\.lists), lists)
        XCTAssertNotNil(model.pipeSession(for: config.id), "the pull did not dial")
    }
}
