import GGChatCore
import XCTest

@testable import GGChatUI

/// A chosen image model the Mac cannot draw with, for a conversation kept
/// on this phone: the switch says why, the menu is there to pick another,
/// and the picture is never drawn with a model nobody chose.
@MainActor
final class ImageModelStaleTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private typealias Choice = ImageModelChoiceTests

    private func opened(_ hub: FakeRunHub, _ drawing: Drawing) async throws -> (AppModel, ProviderConfig) {
        hub.with { $0.drawing = .success(drawing) }
        let (model, config) = try await Runs.makeModel(behind: hub)
        await model.open(config).value
        return (model, config)
    }

    private func conversation(_ model: AppModel) throws -> Conversation {
        try XCTUnwrap(model.selectedConversation)
    }

    private func question(_ model: AppModel) throws -> Message {
        try XCTUnwrap(model.selectedConversation?.messages.last { $0.role == .user })
    }

    /// The Mac's list changes under a choice. A model it no longer lists,
    /// and one it lists without a file, each dim the switch with a sentence
    /// that says so, keep the menu on offer, and leave the choice as it
    /// was: it is not swapped for the default. A message sent then does not
    /// draw, as the switch shows.
    func testAChoiceTheListNoLongerHasIsSaidAndNotSwapped() async throws {
        let hub = FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
        let (model, config) = try await opened(hub, Choice.lists)
        await model.setImageModel(7, for: try conversation(model).id)?.value
        XCTAssertNil(model.drawRefusal(for: try conversation(model)))

        var broken = Choice.qwen
        broken = ImageModelRow(
            id: broken.id, name: broken.name, family: broken.family, complete: false, missing: ["llm", "vae"])
        let gone = Drawing(available: true, model: Choice.flux.name, modelID: 3, models: [Choice.flux])
        let lacking = Drawing(available: true, model: Choice.flux.name, modelID: 3, models: [Choice.flux, broken])
        let sentences = [
            "home no longer has the image model this chat draws with. Pick another from the Draw menu.",
            "qwen_image_2.1-Q8_0 is missing LLM and VAE on home. Pick another from the Draw menu.",
        ]
        for (listed, sentence) in zip([gone, lacking], sentences) {
            model.drawings[config.id] = listed
            model.imageChoiceAnswers[config.id] = nil
            XCTAssertEqual(model.drawRefusal(for: try conversation(model)), sentence)
            XCTAssertEqual(model.drawVerdict(on: config, choosing: 7), .choice(sentence))
            XCTAssertFalse(model.hubCannotDraw(for: try conversation(model)))
            XCTAssertEqual(try conversation(model).imageModelID, 7, "a stale choice was swapped for another")
            let menu = model.drawMenu(for: try conversation(model))
            XCTAssertTrue(menu.isOffered, "nothing to pick another model from")
            XCTAssertEqual(menu.rows.first?.checked, false)
            XCTAssertEqual(model.imageModelToSend(7, to: config), 7)
        }
        XCTAssertNil(model.drawVerdict(on: config, choosing: nil), "the Mac's own pick was refused with the choice")

        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [false])
        XCTAssertFalse(try question(model).draws)

        await model.setImageModel(nil, for: try conversation(model).id)?.value
        XCTAssertNil(model.drawRefusal(for: try conversation(model)))
    }

    /// The Mac refuses a run that names a model it cannot draw with, by
    /// each of its three codes. The question keeps its failure with the
    /// Mac's reason and stays one that draws, the conversation keeps its
    /// choice, and the Mac is asked again what it lists. Retry asks for the
    /// picture again with the same model, even once the list says it is
    /// gone: the Mac refuses again, and nothing is drawn with another.
    func testARunRefusedForItsImageModelKeepsTheQuestionAndTheChoice() async throws {
        for code in AppModel.choiceRefusals.sorted() {
            let hub = FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
            let (model, config) = try await opened(hub, Choice.lists)
            await model.setImageModel(7, for: try conversation(model).id)?.value
            let asked = hub.with(\.drawingAsked)
            hub.with {
                $0.start = .refused(.server(status: 400, code: code, message: "qwen cannot draw here"))
                $0.drawing = .success(
                    Drawing(available: true, model: Choice.flux.name, modelID: 3, models: [Choice.flux]))
                $0.judgements[7] = Drawing(
                    available: false, code: code, reason: "qwen cannot draw here", models: [Choice.flux])
            }
            XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
            try await Runs.until("the refusal") { Runs.settled(model) && model.liveReply == nil }
            XCTAssertEqual(try question(model).failure?.code, code)
            XCTAssertEqual(try question(model).failure?.message, "qwen cannot draw here", code)
            XCTAssertTrue(try question(model).draws, "\(code): the question stopped asking for its picture")
            XCTAssertEqual(try conversation(model).imageModelID, 7, "\(code): the choice was dropped")
            try await Runs.until("the ask") { hub.with(\.drawingAsked) == asked + 1 }
            try await Runs.until("the list") { model.drawings[config.id]?.models == [Choice.flux] }
            try await Runs.until("the judgement") { model.imageChoiceAnswers[config.id]?[7]?.available == false }
            XCTAssertEqual(
                model.drawRefusal(for: try conversation(model)),
                "home cannot draw with the image model this chat chose: qwen cannot draw here", code)

            try await XCTUnwrap(model.retry()).value
            let starts = hub.with { $0.starts.map(\.request) }
            XCTAssertEqual(starts.map(\.draws), [true, true], code)
            XCTAssertEqual(starts.map(\.imageModelID), [7, 7], "\(code): Retry drew with a model nobody chose")
        }
    }

    /// A Mac with several image models and no default cannot draw for a
    /// message that names none, and can for one that names a model. The
    /// Mac is asked about the model chosen, when it is picked and each time
    /// it is asked about drawing, and its answer is what the switch says.
    func testTheMacIsAskedAboutTheModelChosen() async throws {
        let hub = FakeRunHub(frames: [])
        let other = ImageModelRow(id: 3, name: "flux1-schnell-q8_0", family: "flux1")
        let unpicked = Drawing(
            available: false, code: "drawing_unavailable", reason: "there are several image models and no default",
            models: [other, Choice.qwen])
        let (model, config) = try await opened(hub, unpicked)
        let id = try conversation(model).id
        XCTAssertEqual(
            model.drawRefusal(for: try conversation(model)),
            "home cannot draw: there are several image models and no default")
        XCTAssertEqual(hub.with(\.judged), [])
        XCTAssertTrue(model.drawMenu(for: try conversation(model)).isOffered)

        hub.with { $0.judgements[7] = Drawing(available: true, model: Choice.qwen.name, modelID: 7, models: []) }
        await model.setImageModel(7, for: id)?.value
        XCTAssertEqual(hub.with(\.judged), [7])
        XCTAssertNil(model.drawRefusal(for: try conversation(model)), "a model that can draw was refused")
        XCTAssertEqual(model.drawRefusal(on: config), "home cannot draw: there are several image models and no default")

        hub.with {
            $0.judgements[7] = Drawing(
                available: false, code: "image_model_incomplete", reason: "qwen lacks its llm", models: [])
        }
        await model.open(config).value
        XCTAssertEqual(hub.with(\.judged), [7, 7])
        XCTAssertEqual(
            model.drawVerdict(on: config, choosing: 7),
            .choice("home cannot draw with qwen_image_2.1-Q8_0: qwen lacks its llm"))

        hub.with {
            $0.judgements[7] = Drawing(
                available: false, code: "drawing_unavailable", reason: "there is no image runtime", models: [])
        }
        await model.open(config).value
        XCTAssertEqual(model.drawVerdict(on: config, choosing: 7), .hub("home cannot draw: there is no image runtime"))
        XCTAssertTrue(model.hubCannotDraw(for: try conversation(model)))
    }
}
