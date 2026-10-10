import GGChatCore
import XCTest

@testable import GGChatUI

/// Drawing from a conversation kept on this phone: a message sent with Draw
/// pressed starts a run that draws, only on a hub that said it can; the
/// switch is off again once it is sent; and the run's answer says how its
/// events are read.
@MainActor
final class DrawingRunTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    static let can = Drawing(available: true, model: "flux-dev")

    /// A model on `hub`, which says `drawing` of itself, with a conversation
    /// open on it.
    static func makeModel(
        behind hub: FakeRunHub, drawing: Drawing? = can, store: any Store = InMemoryStore()
    ) async throws -> (AppModel, ProviderConfig) {
        let (model, config) = try await Runs.makeModel(behind: hub, store: store)
        model.drawings[config.id] = drawing
        return (model, config)
    }

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    private func question(_ model: AppModel) throws -> Message {
        try XCTUnwrap(model.selectedConversation?.messages.last { $0.role == .user })
    }

    /// With Draw pressed, to a hub that can draw, the run is asked to draw
    /// and the question is kept as one that did; without it the request is
    /// the one it always was, read as the chat route's chunks.
    func testAMessageSentWithDrawStartsARunThatDraws() async throws {
        let hub = hub()
        let (model, _) = try await Self.makeModel(behind: hub)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }
        XCTAssertTrue(try question(model).draws)
        XCTAssertTrue(model.send("and what is a fox?", images: []))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 4 }
        XCTAssertFalse(try question(model).draws)
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, false])
        XCTAssertEqual(hub.with(\.readFrames), [.agent, .openai])
        XCTAssertEqual(hub.with { $0.chats.count }, 0)
    }

    /// A hub that said it cannot draw, one from before drawing and one not
    /// heard from are sent the message as one that does not draw, and the
    /// question is not kept as one that did.
    func testAHubThatCannotDrawIsSentAPlainRun() async throws {
        let cannot = Drawing(available: false, code: "drawing_unavailable", reason: "there is no image model")
        for drawing in [cannot, Drawing(available: false), nil] {
            let hub = hub()
            let (model, _) = try await Self.makeModel(behind: hub, drawing: drawing)
            XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
            try await Runs.until("the reply") { Runs.settled(model) }
            XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [false])
            XCTAssertEqual(hub.with(\.readFrames), [.openai])
            XCTAssertFalse(try question(model).draws)
        }
    }

    /// The switch is the draft's: a draft the model takes leaves an empty
    /// one with the switch off, and one it refuses keeps it.
    func testTheSwitchIsOffAgainOnceTheMessageIsSent() async throws {
        let hub = hub()
        let (model, _) = try await Self.makeModel(behind: hub)
        let open = model.selectedConversationID
        var draft = Draft(text: "a fox in snow", draws: true)
        model.selectedConversationID = nil
        draft.send(through: model)
        XCTAssertTrue(draft.draws, "a refused draft lost its switch")
        XCTAssertEqual(draft.text, "a fox in snow")

        model.selectedConversationID = open
        draft.send(through: model)
        XCTAssertFalse(draft.draws, "the switch stayed on after a send")
        XCTAssertEqual(draft.text, "")
        try await Runs.until("the reply") { Runs.settled(model) }
        draft.text = "and what is a fox?"
        draft.send(through: model)
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 4 }
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, false])
    }

    /// How a run's events are read is what its `PUT` was answered with: a
    /// hub that answers a run that draws with no word on its frames has
    /// them read as chunks, as every run before was.
    func testTheRunsAnswerSaysHowItsEventsAreRead() async throws {
        let hub = hub()
        hub.with { $0.saysNoFrames = true }
        let (model, _) = try await Self.makeModel(behind: hub)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true])
        XCTAssertEqual(hub.with(\.readFrames), [.openai])
    }

    /// A run that ends with one of drawing's codes leaves it on the
    /// question, with the code's own line. Retry asks for the picture again
    /// while the hub can draw; once it cannot, the question goes without
    /// and is no longer one that draws.
    func testRetryAsksForThePictureAgainWhileTheHubCanDraw() async throws {
        let hub = FakeRunHub(frames: [])
        hub.with {
            $0.ending = .failed
            $0.error = RunError(code: "image_generation_failed", message: "sd-server lost the render")
        }
        let (model, config) = try await Self.makeModel(behind: hub)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the failure") { Runs.settled(model) }
        let failed = try question(model)
        XCTAssertEqual(failed.failure?.code, "image_generation_failed")
        XCTAssertEqual(failed.failure?.message, "The reply stopped: sd-server lost the render")
        XCTAssertEqual(failed.failure?.hint, ProviderError.Code.imageGenerationFailed.hint)

        try await XCTUnwrap(model.retry()).value
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, true])
        XCTAssertTrue(try question(model).draws)

        model.drawings[config.id] = Drawing(available: false, code: "drawing_unavailable", reason: "no image model")
        try await XCTUnwrap(model.retry()).value
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, true, false])
        XCTAssertFalse(try question(model).draws)
        XCTAssertEqual(model.selectedConversation?.messages.count, 1, "a retry added a second question")
    }

    /// Continue carries a partial reply on, and never asks for a picture,
    /// though the question it answers did.
    func testContinueNeverAsksForAPicture() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await Self.makeModel(behind: hub)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        model.stop()
        try await Runs.until("the stop") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).isPartial, true)

        hub.with { $0.holdAt = nil }
        try await XCTUnwrap(model.continueReply()).value
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, false])
        XCTAssertEqual(hub.with(\.readFrames).last, .openai)
    }

    /// A hub that refuses to draw for a question, on the `PUT` or by ending
    /// the run, with `drawing_unavailable`, would refuse again: the question
    /// keeps the refusal and stops asking, so Retry sends it without a
    /// picture.
    func testAQuestionAHubRefusedToDrawForStopsAsking() async throws {
        let refusal = ProviderError.server(status: 400, code: "drawing_unavailable", message: "no image model")
        for onThePut in [true, false] {
            let hub = FakeRunHub(frames: [])
            hub.with {
                if onThePut { $0.start = .refused(refusal) }
                $0.ending = .failed
                $0.error = RunError(code: "drawing_unavailable", message: "no image model")
            }
            let (model, _) = try await Self.makeModel(behind: hub)
            XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
            try await Runs.until("the refusal") { Runs.settled(model) && model.liveReply == nil }
            XCTAssertEqual(try question(model).failure?.code, "drawing_unavailable")
            XCTAssertFalse(try question(model).draws, "a refused question still asks to draw")

            hub.with {
                $0.start = .runs
                $0.ending = .completed
                $0.error = nil
            }
            try await XCTUnwrap(model.retry()).value
            XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, false])
        }
    }

    /// What a Mac said of drawing is forgotten when its provider is moved
    /// to another Mac: the answer was the old one's. The switch then says
    /// it is not known yet, and a message sent with it on does not draw.
    func testAProviderMovedToAnotherMacForgetsWhetherItCanDraw() async throws {
        let hub = hub()
        let (model, config) = try await Self.makeModel(behind: hub)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertNil(model.drawRefusal(for: conversation))

        var moved = config
        moved.kind = .pipe(ticketDigest: "another-mac")
        model.updateProvider(moved)
        XCTAssertEqual(model.drawRefusal(for: conversation), "It is not known yet whether home can draw.")
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [false])
        XCTAssertFalse(try question(model).draws)
    }

    /// A run whose answer says its events are written some way this build
    /// does not know is not read as chunks or as an agent's: it is stopped
    /// on the hub, and the question says why in a plain sentence.
    func testARunWrittenAWayThisBuildCannotReadIsGivenUp() async throws {
        let hub = hub()
        hub.with { $0.saysFrames = .unknown }
        let (model, _) = try await Self.makeModel(behind: hub)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the end") { Runs.settled(model) && model.liveReply == nil }
        try await Runs.until("the cancel") { hub.with(\.cancels).count == 1 }
        XCTAssertEqual(hub.with(\.reads).count, 0, "a run that cannot be read was read")
        XCTAssertEqual(model.selectedConversation?.messages.count, 1)
        XCTAssertEqual(
            try question(model).failure?.message,
            "home is writing this reply in a way this version of the app cannot read.")
        XCTAssertEqual(hub.with(\.cancels), hub.with { $0.starts.map(\.id) })
    }
}
