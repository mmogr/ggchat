import GGChatCore
import XCTest

@testable import GGChatUI

/// Which image model draws, for a conversation kept on this phone: the
/// choice is the conversation's, said with each message that draws to a hub
/// that lists its image models, and never swapped for another.
@MainActor
final class ImageModelChoiceTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    static let flux = ImageModelRow(
        id: 3, name: "flux1-schnell-q8_0", family: "flux1", isDefault: true, resident: true)
    static let qwen = ImageModelRow(id: 7, name: "qwen_image_2.1-Q8_0", family: "qwen-image-2.1")
    static let sdxl = ImageModelRow(id: 9, name: "sdxl-base", family: "sdxl", complete: false, missing: ["vae"])
    /// A Mac with three image models: a default, another, and one that
    /// lacks a file.
    static let lists = Drawing(available: true, model: flux.name, modelID: 3, models: [flux, qwen, sdxl])
    /// A Mac from before the list.
    static let older = Drawing(available: true, model: "flux-dev")

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    /// A model on a hub that says `drawing` of itself, asked and answered.
    private func opened(_ hub: FakeRunHub, _ drawing: Drawing = lists) async throws -> (AppModel, ProviderConfig) {
        hub.with { $0.drawing = .success(drawing) }
        let (model, config) = try await Runs.makeModel(behind: hub)
        await model.open(config).value
        return (model, config)
    }

    private func conversation(_ model: AppModel) throws -> Conversation {
        try XCTUnwrap(model.selectedConversation)
    }

    private func send(_ text: String, draws: Bool, _ model: AppModel) async throws {
        let before = try conversation(model).messages.count
        XCTAssertTrue(model.send(text, images: [], draws: draws))
        try await Runs.until("the reply") {
            Runs.settled(model) && model.selectedConversation?.messages.count == before + 2
        }
    }

    /// What each run was started saying of drawing: whether it draws, and
    /// with which image model.
    private func said(_ hub: FakeRunHub) -> [String] {
        hub.with { $0.starts.map { "\($0.request.draws) \($0.request.imageModelID.map(String.init) ?? "-")" } }
    }

    /// A Mac from before the list has no menu, takes no choice, and is
    /// never sent `image_model`, even by a conversation that holds a choice
    /// from before: it would refuse the run for a word it does not know.
    func testAnOlderMacHasNoMenuAndIsNeverSentAnImageModel() async throws {
        let hub = hub()
        let (model, _) = try await opened(hub, Self.older)
        XCTAssertEqual(model.drawMenu(for: try conversation(model)), .none)
        XCTAssertNil(model.setImageModel(7, for: try conversation(model).id))
        XCTAssertNil(try conversation(model).imageModelID, "a choice was taken from a Mac that lists no models")

        var held = try conversation(model)
        held.imageModelID = 7
        model.update(held)
        XCTAssertEqual(model.drawMenu(for: try conversation(model)), .none)
        XCTAssertNil(model.drawRefusal(for: try conversation(model)))
        try await send("a fox in snow", draws: true, model)
        XCTAssertEqual(said(hub), ["true -"])
        XCTAssertEqual(hub.with(\.judged), [], "a Mac from before the list was asked to judge a model")
    }

    /// A choice is said with each message that draws, the next one too, and
    /// with no message that does not. It is kept with the conversation, and
    /// with none chosen a message that draws names none.
    func testAChoiceIsSaidWithEachMessageThatDrawsAndNoOther() async throws {
        let hub = hub()
        let store = InMemoryStore()
        hub.with { $0.drawing = .success(Self.lists) }
        let (model, config) = try await Runs.makeModel(behind: hub, store: store)
        await model.open(config).value
        try await send("a fox in snow", draws: true, model)
        await model.setImageModel(7, for: try conversation(model).id)?.value
        XCTAssertEqual(try conversation(model).imageModelID, 7)
        XCTAssertEqual(try store.loadConversations().first?.imageModelID, 7)
        XCTAssertNil(model.drawRefusal(for: try conversation(model)))
        try await send("and an owl", draws: true, model)
        try await send("what is an owl?", draws: false, model)
        try await send("and a hare", draws: true, model)
        XCTAssertEqual(said(hub), ["true -", "true 7", "false -", "true 7"])
        XCTAssertEqual(try conversation(model).imageModelID, 7, "the choice was forgotten once it was sent")

        await model.setImageModel(nil, for: try conversation(model).id)?.value
        XCTAssertNil(try store.loadConversations().first?.imageModelID)
        try await send("and a stoat", draws: true, model)
        XCTAssertEqual(said(hub).last, "true -")
    }

    /// Only a model the Mac's list has with all its files can be chosen:
    /// one that lacks a file and one the list does not have are not taken,
    /// and the choice stays as it was.
    func testAModelWithoutItsFilesCannotBeChosen() async throws {
        let hub = hub()
        let (model, _) = try await opened(hub)
        let id = try conversation(model).id
        XCTAssertNil(model.setImageModel(9, for: id), "a model missing a file was chosen")
        XCTAssertNil(model.setImageModel(42, for: id), "a model the Mac does not list was chosen")
        XCTAssertNil(try conversation(model).imageModelID)
        await model.setImageModel(7, for: id)?.value
        XCTAssertNil(model.setImageModel(9, for: id))
        XCTAssertEqual(try conversation(model).imageModelID, 7)
    }

    /// An id names a model on one machine. A provider moved to another Mac
    /// takes the choice of each of its conversations with it, in the store
    /// too. An edit that leaves it on the same Mac does not.
    func testAProviderMovedToAnotherMacForgetsTheChoice() async throws {
        let hub = hub()
        let store = InMemoryStore()
        hub.with { $0.drawing = .success(Self.lists) }
        let (model, config) = try await Runs.makeModel(behind: hub, store: store)
        await model.open(config).value
        let id = try conversation(model).id
        await model.setImageModel(7, for: id)?.value

        var renamed = config
        renamed.name = "study"
        model.updateProvider(renamed)
        XCTAssertEqual(try conversation(model).imageModelID, 7, "a rename forgot the choice")

        var moved = renamed
        moved.kind = .pipe(ticketDigest: "another-mac")
        model.updateProvider(moved)
        XCTAssertNil(try conversation(model).imageModelID)
        XCTAssertNil(try store.loadConversations().first { $0.id == id }?.imageModelID)
        XCTAssertNil(model.imageChoiceAnswers[config.id])
    }
}
