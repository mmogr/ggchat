import GGChatCore
import XCTest

@testable import GGChatUI

/// Which image model draws, for a Mac's chat: the choice is held with the
/// chat open, said with each turn that draws to a Mac that lists its image
/// models, and never written to this phone or swapped for another.
@MainActor
final class HubChatImageModelTests: XCTestCase {
    private typealias Choice = ImageModelChoiceTests

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// Chat 12 open behind a Mac that says `drawing` of itself, once the
    /// phone has heard it.
    private func opened(
        _ drawing: Drawing, store: any Store = InMemoryStore()
    ) async throws -> (AppModel, FakeChatsHub) {
        let hub = FakeChatsHub()
        hub.runs.with { $0.drawing = .success(drawing) }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        try await until("the ask") { hub.runs.with(\.drawingAsked) > 0 && model.opening[config.id] == nil }
        await model.catchUp(config.id, quietly: true)
        return (model, hub)
    }

    private func send(_ text: String, draws: Bool, through model: AppModel) async throws {
        model.sendToHubChat(text, draws: draws)
        try await until("the reply's end") { model.hubReplies.isEmpty }
    }

    /// A Mac from before the list has no menu, takes no choice, and its
    /// turn never says `image_model`, even with a choice held: it refuses a
    /// body with a key it does not know.
    func testAnOlderMacHasNoMenuAndItsTurnNeverNamesAnImageModel() async throws {
        let (model, hub) = try await opened(Choice.older)
        XCTAssertEqual(model.hubDrawMenu, .none)
        XCTAssertNil(model.setHubImageModel(7))
        XCTAssertNil(model.openedHubChat?.imageModel, "a choice was taken from a Mac that lists no models")

        model.openedHubChat?.imageModel = 7
        XCTAssertEqual(model.hubDrawMenu, .none)
        XCTAssertNil(model.hubDrawRefusal)
        try await send("a fox in snow", draws: true, through: model)
        XCTAssertEqual(
            hub.with { $0.turns.map(\.turn) }, [HubTurn(conversationID: 12, content: "a fox in snow", draw: true)])
        XCTAssertEqual(hub.runs.with(\.judged), [])
    }

    /// The choice is said with each turn that draws, the next one too, and
    /// with no turn that does not. A model that lacks a file cannot be
    /// chosen. Nothing of the choice is written to this phone, and a chat
    /// opened again has none: the Mac keeps no such choice either.
    func testAChoiceIsSaidWithEachTurnThatDrawsAndHeldOnlyWithTheChatOpen() async throws {
        let store = InMemoryStore()
        let (model, hub) = try await opened(Choice.lists, store: store)
        let providerID = try XCTUnwrap(model.openedHubChat).providerID
        XCTAssertEqual(model.hubDrawMenu.rows.map(\.title).first, "Default (flux1-schnell-q8_0)")
        try await send("a fox in snow", draws: true, through: model)
        XCTAssertNil(model.setHubImageModel(9), "a model missing a file was chosen")
        await model.setHubImageModel(7)?.value
        XCTAssertEqual(hub.runs.with(\.judged), [7])
        XCTAssertEqual(model.hubDrawMenu.rows.map(\.checked), [false, false, true, false])
        try await send("and an owl", draws: true, through: model)
        try await send("what is an owl?", draws: false, through: model)
        try await send("and a hare", draws: true, through: model)
        XCTAssertEqual(
            hub.with { $0.turns.map(\.turn) },
            [
                HubTurn(conversationID: 12, content: "a fox in snow", draw: true),
                HubTurn(conversationID: 12, content: "and an owl", draw: true, imageModel: 7),
                HubTurn(conversationID: 12, content: "what is an owl?"),
                HubTurn(conversationID: 12, content: "and a hare", draw: true, imageModel: 7),
            ])
        XCTAssertEqual(try store.loadConversations().compactMap(\.imageModelID), [])

        model.selection = nil
        try await until("the chat's leaving") { model.openedHubChat == nil }
        model.selection = .hub(providerID: providerID, chatID: 12)
        try await until("the rows") { model.openedHubChat?.state.showsRows == true }
        XCTAssertNil(model.openedHubChat?.imageModel)
    }

    /// The Mac refuses a turn that names a model it cannot draw with. The
    /// view says so with the Mac's reason, the draft comes back with Draw as
    /// it was, the chat keeps its choice, and the Mac is asked again what
    /// it lists. The switch then says why, and the menu is there to pick
    /// another: nothing is sent with a model nobody chose.
    func testATurnRefusedForItsImageModelGivesTheDraftBackAndKeepsTheChoice() async throws {
        for code in AppModel.choiceRefusals.sorted() {
            let (model, hub) = try await opened(Choice.lists)
            await model.setHubImageModel(7)?.value
            let asked = hub.runs.with(\.drawingAsked)
            hub.with {
                $0.turnFailure = .refused(.server(status: 400, code: code, message: "qwen cannot draw here"))
            }
            hub.runs.with {
                $0.drawing = .success(
                    Drawing(available: true, model: Choice.flux.name, modelID: 3, models: [Choice.flux]))
                $0.judgements[7] = nil
            }
            model.sendToHubChat("a fox in snow", draws: true)
            try await until("the refusal with \(code)") { model.openedHubChat?.unsent != nil }
            XCTAssertEqual(hub.with { $0.turns.map(\.turn.imageModel) }, [7], code)
            XCTAssertEqual(model.openedHubChat?.notice?.contains("qwen cannot draw here"), true, code)
            XCTAssertEqual(model.openedHubChat?.imageModel, 7, "\(code): the choice was dropped")
            XCTAssertEqual(hub.runs.with(\.drawingAsked), asked + 1, "\(code): the list was not read again")
            let back = try XCTUnwrap(model.takeUnsentHubDraft(), code)
            XCTAssertEqual(back.text, "a fox in snow", code)
            XCTAssertTrue(back.draws, code)
            XCTAssertTrue(model.hubDrawMenu.isOffered, "\(code): nothing to pick another model from")

            hub.runs.with { $0.judgements = [:] }
            model.imageChoiceAnswers = [:]
            XCTAssertEqual(
                model.hubDrawRefusal,
                "home no longer has the image model this chat draws with. Pick another from the Draw menu.", code)
        }
    }
}
