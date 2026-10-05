import GGChatCore
import XCTest

@testable import GGChatUI

/// Which model a Mac's chat runs on, and what that Mac's model list says of
/// it: the list is read when a chat is opened and again each time the pipe
/// comes up, and it decides the Thinking switch and whether images are sent.
@MainActor
final class HubChatModelListTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private typealias Thinking = HubChatThinkingTests

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await Runs.until(what, condition)
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// Opens chat `id` again, so its rows are read again.
    private func reopen(_ model: AppModel, on config: ProviderConfig, chat id: Int64 = 12) async throws {
        model.selection = nil
        model.selection = .hub(providerID: config.id, chatID: id)
        try await until("the rows") { model.openedHubChat?.state != .reading }
    }

    /// The far machine goes away and the pipe is dialled again, as the
    /// reconnect pill does.
    private func dropAndReconnect(_ config: ProviderConfig, of model: AppModel) async throws {
        let session = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        session.dropped()
        try await until("the close") { model.pipeStatus(for: config.id) == .closed }
        // The drop says why it closed; that sentence is not what this is about.
        model.lastError = nil
        await model.reconnectPipe(for: config)
        try await until("the pipe") { model.pipeStatus(for: config.id) == .direct }
    }

    /// A row the Mac saved for a reply by `modelName`.
    private func reply(by modelName: String?) -> HubMessage {
        HubMessage(
            id: 43, conversationID: 12, role: "assistant", content: "A dependency moved.", createdAt: "e",
            metadata: HubMessageMetadata(modelName: modelName))
    }

    /// The switch is there only for a model the Mac lists now as one that
    /// thinks. The chat's model is the one its settings name, else its last
    /// reply's, else the one the list of chats gives it, each looked up in
    /// the Mac's models; a chat that names none, a model the Mac does not
    /// list, one it lists without `reasoning`, and a chat that cannot be read
    /// have no switch. Whether images are sent asks the same model.
    func testTheSwitchIsHiddenWhenTheModelIsNotInTheMacsList() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        XCTAssertEqual(model.models(for: config.id).map(\.id), ["mock-27b", "mock-4b"])
        XCTAssertFalse(model.hubChatOffersThinking, "a model the Mac does not list was offered the switch")

        let listed = [
            ModelInfo(id: "qwen3-8b", capabilities: ["reasoning"]), ModelInfo(id: "plain-4b"),
            ModelInfo(id: "seer-9b", capabilities: ["vision", "reasoning"]),
        ]
        model.modelsByProvider[config.id] = listed
        XCTAssertTrue(model.hubChatOffersThinking, "the model the list of chats names thinks")
        model.modelsByProvider[config.id] = [ModelInfo(id: "qwen3-8b", capabilities: ["vision"])]
        XCTAssertFalse(model.hubChatOffersThinking, "a model listed without reasoning was offered the switch")
        model.modelsByProvider[config.id] = listed

        // The names the chat's settings and its last reply give, and then
        // whether the switch is there and whether images are sent.
        let cases: [([String?], [Bool])] = [
            ([nil, nil], [true, false]), ([nil, "plain-4b"], [false, false]), ([nil, "seer-9b"], [true, true]),
            (["plain-4b", "seer-9b"], [false, false]), (["seer-9b", "plain-4b"], [true, true]),
            (["qwen3-8b", "plain-4b"], [true, false]), (["gone-2b", "qwen3-8b"], [false, true]),
        ]
        for (names, want) in cases {
            let rows = Array(FakeChatsHub.opened.messages.dropLast()) + [reply(by: names[1])]
            let chat = FakeChatsHub.opened.with(HubChatSettings(modelName: names[0]), rows: rows)
            hub.with { $0.chats[12] = chat }
            try await reopen(model, on: config)
            let open = try XCTUnwrap(model.openedHubChat)
            XCTAssertEqual([model.hubChatOffersThinking, model.canSeeHubChat(open)], want, "\(names)")
        }

        // Chat 9 names no model anywhere.
        hub.with { $0.chats[9] = HubChatOpen(conversation: FakeChatsHub.opened.conversation, messages: []) }
        try await reopen(model, on: config, chat: 9)
        XCTAssertEqual(model.openedHubChat?.state, .read([]))
        XCTAssertFalse(model.hubChatOffersThinking, "a chat that names no model was offered the switch")

        hub.with { state in
            state.chats[12] = FakeChatsHub.opened
            state.openFailure = .notFound
        }
        try await reopen(model, on: config)
        XCTAssertEqual(model.openedHubChat?.state, .unavailable("home no longer has this chat."))
        XCTAssertFalse(model.hubChatOffersThinking, "a chat that could not be read was offered the switch")
    }

    /// The chat's model is its last reply that names one, so a newer reply
    /// that names none, as one that did not finish, does not hide it. gglib's
    /// own recorded chat has this shape. Chat 9's row in the list of chats
    /// names no model, so only a reply can.
    func testAReplyThatNamesNoModelDoesNotHideTheOneBeforeIt() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.modelsByProvider[config.id] = Thinking.models
        let unfinished = HubMessage(id: 44, conversationID: 9, role: "assistant", content: "Pin the", createdAt: "f")
        let rows = [reply(by: "qwen3-8b"), unfinished]
        hub.with { $0.chats[9] = HubChatOpen(conversation: FakeChatsHub.opened.conversation, messages: rows) }
        try await reopen(model, on: config, chat: 9)
        XCTAssertEqual(model.openedHubChat?.state.showsRows, true)
        XCTAssertTrue(model.hubChatOffersThinking, "a reply that names no model hid the one before it")
    }

    /// Opening one of a Mac's chats lists that Mac's models when this phone
    /// has none, and not again when it has. A chat opened while the pipe is
    /// down asks nothing then, and lists once the pipe is up.
    func testOpeningAChatListsTheMacsModels() async throws {
        let hub = Thinking.hub()
        let (model, config) = try await Runs.makeModel(behind: hub)
        try await until("the list") { model.hubChats[config.id] != nil && model.hubListing.isEmpty }
        await settle()
        XCTAssertEqual(hub.with(\.modelLists), 0, "the models were listed before anything was opened")
        XCTAssertFalse(model.hubChatOffersThinking)

        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the models") { model.models(for: config.id) == Thinking.models }
        try await until("the rows") { model.openedHubChat?.state.showsRows == true }
        XCTAssertTrue(model.hubChatOffersThinking)
        XCTAssertEqual(hub.with(\.modelLists), 1)
        XCTAssertNil(model.lastError)
        try await reopen(model, on: config)
        await settle()
        XCTAssertEqual(hub.with(\.modelLists), 1, "a list this phone already had was asked for on opening")

        let away = Thinking.hub()
        let (other, home) = try await Runs.makeModel(behind: away)
        try await until("the list") { other.hubChats[home.id] != nil && other.hubListing.isEmpty }
        await other.disconnectPipe(for: home.id, leaving: .closed)
        other.selection = .hub(providerID: home.id, chatID: 12)
        await settle()
        XCTAssertEqual(away.with(\.modelLists), 0, "a Mac out of reach was asked for its models")
        XCTAssertFalse(other.hubChatOffersThinking)
        await other.connectPipe(for: home)
        try await until("the models") { other.models(for: home.id) == Thinking.models }
        try await until("the rows") { other.openedHubChat?.state.showsRows == true }
        XCTAssertTrue(other.hubChatOffersThinking, "the pipe came up and the switch did not")
        XCTAssertEqual(away.with(\.modelLists), 1)
    }

    /// The list asked for by opening a chat is one nobody asked for, so one
    /// that fails raises no alert, and the chat opens without a switch.
    func testAListThatFailsOnOpeningAChatRaisesNoAlert() async throws {
        let hub = Thinking.hub()
        hub.with { $0.losesModelLists = true }
        let (model, config) = try await Runs.makeModel(behind: hub)
        try await until("the list") { model.hubChats[config.id] != nil && model.hubListing.isEmpty }
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the list that fails") { hub.with(\.modelLists) == 1 }
        try await until("the rows") { model.openedHubChat?.state.showsRows == true }
        await settle()
        XCTAssertNil(model.lastError, "a list nobody asked for raised an alert when it failed")
        XCTAssertTrue(model.models(for: config.id).isEmpty)
        XCTAssertFalse(model.hubChatOffersThinking)
    }

    /// A pipe that comes back lists its Mac's models again, since a model
    /// may have changed there meanwhile: one that no longer thinks loses its
    /// switch. A list that fails then keeps the one before and raises no
    /// alert, and the next time the pipe comes up it is asked again.
    func testAPipeComingUpListsAgainAndAFailedListKeepsTheOld() async throws {
        let hub = Thinking.hub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        XCTAssertTrue(model.hubChatOffersThinking)
        XCTAssertEqual(hub.with(\.modelLists), 1)

        let changed = [ModelInfo(id: "qwen3-8b"), ModelInfo(id: "new-12b", capabilities: ["reasoning"])]
        hub.with { $0.models = changed }
        try await dropAndReconnect(config, of: model)
        try await until("the models listed again") { model.models(for: config.id) == changed }
        XCTAssertEqual(hub.with(\.modelLists), 2)
        XCTAssertNotNil(model.openedHubChat, "the chat was dropped with its pipe")
        XCTAssertFalse(model.hubChatOffersThinking, "a model that no longer thinks kept its switch")

        hub.with { state in
            state.models = Thinking.models
            state.losesModelLists = true
        }
        try await dropAndReconnect(config, of: model)
        try await until("the list that fails") { hub.with(\.modelLists) == 3 }
        await settle()
        XCTAssertEqual(model.models(for: config.id), changed, "a list that failed took the one before with it")
        XCTAssertNil(model.lastError, "a list nobody asked for raised an alert when it failed")

        hub.with { $0.losesModelLists = false }
        try await dropAndReconnect(config, of: model)
        try await until("the models listed again") { model.models(for: config.id) == Thinking.models }
        XCTAssertEqual(hub.with(\.modelLists), 4)
        XCTAssertTrue(model.hubChatOffersThinking)
    }
}
