import GGChatCore
import XCTest

@testable import GGChatUI

/// Drawing from a Mac's chat: a turn says `draw` only for a message sent
/// with Draw pressed to a Mac that said it can draw, and the switch is off
/// again once the message is sent.
@MainActor
final class HubChatDrawTests: XCTestCase {
    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// Chat 12 open behind a Mac that says `drawing` of itself, once the
    /// phone has heard it.
    private func opened(_ drawing: Drawing?) async throws -> (AppModel, FakeChatsHub) {
        let hub = FakeChatsHub()
        hub.runs.with { $0.drawing = drawing.map { .success($0) } ?? .failure(.transport("lost")) }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        try await until("the ask") { hub.runs.with(\.drawingAsked) > 0 && model.opening[config.id] == nil }
        await model.catchUp(config.id, quietly: true)
        return (model, hub)
    }

    private static let can = Drawing(available: true, model: "flux-dev")

    /// Sends one message and waits for its reply to end.
    private func send(_ text: String, draws: Bool, through model: AppModel) async throws {
        model.sendToHubChat(text, draws: draws)
        try await until("the reply's end") { model.hubReplies.isEmpty }
    }

    /// With the switch on, to a Mac that can draw, the turn says `draw`;
    /// with it off the turn is the two keys it always was.
    func testATurnSaysDrawOnlyWhenTheSwitchIsOn() async throws {
        let (model, hub) = try await opened(Self.can)
        try await send("a fox in snow", draws: true, through: model)
        try await send("and what is a fox?", draws: false, through: model)
        XCTAssertEqual(
            hub.with { $0.turns.map(\.turn) },
            [
                HubTurn(conversationID: 12, content: "a fox in snow", draw: true),
                HubTurn(conversationID: 12, content: "and what is a fox?"),
            ])
    }

    /// A Mac that said it cannot draw, one from before drawing and one that
    /// never answered are each sent the message without the word, switch on
    /// or not: an older gglib refuses a key it does not know.
    func testAMacThatCannotDrawIsNeverSentTheWord() async throws {
        let cannot = Drawing(available: false, code: "drawing_unavailable", reason: "there is no image model")
        for drawing in [cannot, Drawing(available: false), nil] {
            let (model, hub) = try await opened(drawing)
            XCTAssertNotNil(model.hubDrawRefusal)
            try await send("a fox in snow", draws: true, through: model)
            XCTAssertEqual(hub.with { $0.turns.map(\.turn) }, [HubTurn(conversationID: 12, content: "a fox in snow")])
        }
    }

    /// The switch is the draft's: the draft a send leaves is empty with the
    /// switch off, so the next message does not draw unless it is pressed
    /// again.
    func testTheSwitchIsOffAgainOnceTheMessageIsSent() async throws {
        let (model, hub) = try await opened(Self.can)
        var draft = Draft(text: "a fox in snow", draws: true)
        draft.sendToHubChat(through: model)
        XCTAssertFalse(draft.draws, "the switch stayed on after a send")
        XCTAssertEqual(draft.text, "")
        try await until("the reply's end") { model.hubReplies.isEmpty }

        draft.text = "and what is a fox?"
        draft.sendToHubChat(through: model)
        try await until("the reply's end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.with { $0.turns.map(\.turn.draw) }, [true, false])
    }

    /// A turn the Mac refuses gives its draft back with Draw as it was, and
    /// one whose answer was lost is put again saying the same.
    func testARefusedTurnKeepsItsSwitchAndALostOneIsPutAgainWithIt() async throws {
        let (model, hub) = try await opened(Self.can)
        hub.with { $0.turnFailure = .noModel }
        model.sendToHubChat("a fox in snow", draws: true)
        try await until("the refusal") { model.openedHubChat?.unsent != nil }
        let back = try XCTUnwrap(model.takeUnsentHubDraft())
        XCTAssertEqual(back.text, "a fox in snow")
        XCTAssertTrue(back.draws, "a refused draft lost its switch")

        hub.with {
            $0.turnFailure = nil
            $0.turnsLost = 1
            $0.turns = []
        }
        model.sendToHubChat(back.text, draws: back.draws)
        try await until("the lost answer") { hub.with(\.turns).count == 1 && model.openHubReply?.reading == nil }
        await model.scene(.foreground).value
        try await until("the second answer") { hub.with(\.turns).count == 2 }
        XCTAssertEqual(hub.with { $0.turns.map(\.turn.draw) }, [true, true])
    }

    /// The Mac starts a turn's run before it loads the model, so it can
    /// refuse the turn by ending the run: failed, with `model_unavailable`,
    /// `unavailable` or `conflict`, and no row saved. Each, and the two
    /// codes a `PUT` answers should a run ever end with one, is said as a
    /// refused turn is, with the code's own line when it has one; the draft
    /// comes back with Draw as it was, the run is not kept as one to read
    /// on, and the Mac's rows are not read again. A run that fails any other
    /// way, or after something of the reply came, ends as a reply that
    /// stopped, and gives nothing back.
    func testARunThatEndsAsARefusalGivesTheDraftBack() async throws {
        XCTAssertEqual(
            AppModel.turnRefusals,
            ["model_unavailable", "unavailable", "conflict", "drawing_unavailable", "image_model_cannot_chat"])
        let store = InMemoryStore()
        let hub = FakeChatsHub(reply: [])
        hub.runs.with {
            $0.drawing = .success(Self.can)
            $0.ending = .failed
        }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        try await until("the ask") { model.hubDrawRefusal == nil }
        for code in AppModel.turnRefusals.sorted() {
            hub.runs.with { $0.error = RunError(code: code, message: "it was refused") }
            model.sendToHubChat("a fox in snow", draws: true)
            try await until("the refusal with \(code)") { model.openedHubChat?.unsent != nil }
            let hint = ProviderError.hint(forCode: code, on: .unknown)
            XCTAssertEqual(
                model.openedHubChat?.notice,
                ["home did not take this message. it was refused", hint].compactMap(\.self).joined(separator: " "),
                code)
            XCTAssertEqual(model.hubReplies.count, 0, code)
            XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [], "\(code): the run was kept to read on")
            XCTAssertEqual(hub.with(\.opens), [12], "\(code): rows were read for a turn that saved none")
            let back = try XCTUnwrap(model.takeUnsentHubDraft(), code)
            XCTAssertEqual(back.text, "a fox in snow", code)
            XCTAssertTrue(back.draws, code)
        }

        hub.runs.with { $0.error = RunError(code: "upstream_error", message: "the model server stopped") }
        model.sendToHubChat("a fox in snow", draws: true)
        try await until("the end") { model.hubReplies.isEmpty && model.openedHubChat?.notice != nil }
        XCTAssertEqual(model.openedHubChat?.notice, "The reply stopped on home: the model server stopped")
        XCTAssertNil(model.openedHubChat?.unsent)

        let late = FakeChatsHub(reply: [[.tool("Generate Image")]])
        late.runs.with {
            $0.ending = .failed
            $0.error = RunError(code: "unavailable", message: "the model was stopped")
        }
        let (other, _) = try await HubChatContinueTests.opened(late)
        other.sendToHubChat("a fox in snow")
        try await until("the end") { other.hubReplies.isEmpty && other.openedHubChat?.notice != nil }
        XCTAssertEqual(other.openedHubChat?.notice, "The reply stopped on home: the model was stopped")
        XCTAssertNil(other.openedHubChat?.unsent)
    }
}
