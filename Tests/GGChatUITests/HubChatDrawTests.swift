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
}
