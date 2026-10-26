import GGChatCore
import XCTest

@testable import GGChatUI

/// A paired Mac whose answer about drawing names the MCP servers it offers:
/// every question to it is a run with gglib's tools, drawing or not, read
/// as an agent's; a Mac that names none, and a gglib reached by address,
/// are sent what they were.
@MainActor
final class ToolsOfferedRunTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    private func question(_ model: AppModel) throws -> Message {
        try XCTUnwrap(model.selectedConversation?.messages.last { $0.role == .user })
    }

    private func runsTools(_ hub: FakeRunHub) -> [Bool] {
        hub.with { $0.starts.map(\.request.runsTools) }
    }

    /// A plain question and one sent with Draw both run with the tools, and
    /// only the second draws; both are read as an agent's, and nothing goes
    /// by the chat route.
    func testAMacThatOffersToolsHasEveryQuestionRunWithThem() async throws {
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: Drawing.offersTavily)
        XCTAssertTrue(model.send("what is new in Swift?", images: []))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 4 }
        XCTAssertEqual(runsTools(hub), [true, true])
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [false, true])
        XCTAssertEqual(hub.with(\.readFrames), [.agent, .agent])
        XCTAssertEqual(hub.with { $0.chats.count }, 0)
    }

    /// A Mac with no image model that names servers still runs their
    /// tools: a message sent with Draw on goes with them and without
    /// drawing, and the question is not kept as one that drew.
    func testAMacThatCannotDrawStillRunsItsTools() async throws {
        let hub = hub()
        let cannot = Drawing(
            available: false, code: "drawing_unavailable", reason: "there is no image model",
            mcpServers: [OfferedServer(id: 3, name: "tavily")])
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: cannot)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertEqual(runsTools(hub), [true])
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [false])
        XCTAssertEqual(hub.with(\.readFrames), [.agent])
        XCTAssertFalse(try question(model).draws)
    }

    /// A Mac whose answer names no servers, one from before the list and
    /// one not heard from are sent a plain question as they always were.
    func testAMacThatNamesNoServersIsSentWhatItWas() async throws {
        let none = Drawing(available: true, model: "flux-dev", mcpServers: [])
        for drawing in [none, DrawingRunTests.can, nil] {
            let hub = hub()
            let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: drawing)
            XCTAssertTrue(model.send("what is new in Swift?", images: []))
            try await Runs.until("the reply") { Runs.settled(model) }
            XCTAssertEqual(runsTools(hub), [false], String(describing: drawing))
            XCTAssertEqual(hub.with(\.readFrames), [.openai], String(describing: drawing))
        }
    }

    /// Retry asks the question again, with the tools; Continue carries a
    /// reply's words on, and runs none.
    func testRetryRunsTheToolsAndContinueDoesNot() async throws {
        let failing = FakeRunHub(frames: [])
        failing.with {
            $0.ending = .failed
            $0.error = RunError(code: "upstream_error", message: "the model stopped answering")
        }
        let (retried, _) = try await DrawingRunTests.makeModel(behind: failing, drawing: Drawing.offersTavily)
        XCTAssertTrue(retried.send("what is new in Swift?", images: []))
        try await Runs.until("the failure") { Runs.settled(retried) && retried.liveReply == nil }
        XCTAssertEqual(retried.selectedConversation?.messages.count, 1)
        try await XCTUnwrap(retried.retry()).value
        XCTAssertEqual(runsTools(failing), [true, true])
        XCTAssertEqual(failing.with(\.readFrames), [.agent, .agent])

        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: Drawing.offersTavily)
        XCTAssertTrue(model.send("what is new in Swift?", images: []))
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        model.stop()
        try await Runs.until("the stop") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).isPartial, true)
        hub.with { $0.holdAt = nil }
        try await XCTUnwrap(model.continueReply()).value
        XCTAssertEqual(runsTools(hub), [true, false])
        XCTAssertEqual(hub.with(\.readFrames).last, .openai)
    }

    /// A gglib reached by address is never sent the tools, whatever it
    /// says of its servers: only a paired Mac is.
    func testAGglibByAddressIsNeverSentTools() async throws {
        let hub = hub()
        let (model, config) = try await Runs.makeModel(behind: hub, direct: true)
        model.drawings[config.id] = Drawing.offersTavily
        XCTAssertTrue(model.send("what is new in Swift?", images: []))
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertEqual(runsTools(hub), [false])
        XCTAssertEqual(hub.with(\.readFrames), [.openai])
    }

    /// A question whose PUT lost its answer is put again under its id with
    /// the tools it was first sent with, and read as an agent's.
    func testAQuestionPutAgainAfterItsAnswerWasLostCarriesTheTools() async throws {
        let hub = hub()
        hub.with { $0.putsLost = 1 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = Drawing.offersTavily
        try await XCTUnwrap(model.send("go")).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertEqual(runsTools(hub), [true, true])
        XCTAssertEqual(hub.with(\.readFrames), [.agent])
    }

    /// A Continue whose PUT lost its answer is put again as it was first
    /// sent: with no tools, and read as the chat route's chunks.
    func testAContinuePutAgainAfterItsAnswerWasLostRunsNoTools() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = Drawing.offersTavily
        XCTAssertTrue(model.send("what is new in Swift?", images: []))
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        model.stop()
        try await Runs.until("the stop") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).isPartial, true)
        hub.with {
            $0.holdAt = nil
            $0.putsLost = 1
        }
        try await XCTUnwrap(model.continueReply()).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertEqual(hub.with { $0.starts.count }, 3, "the lost PUT was not sent again")
        XCTAssertEqual(runsTools(hub), [true, false, false])
        XCTAssertEqual(hub.with(\.readFrames).last, .openai)
    }
}
