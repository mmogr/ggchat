import GGChatCore
import XCTest

@testable import GGChatUI

/// A paired Mac whose answer about drawing names the MCP servers it offers:
/// a question names, by id, the servers its conversation picked that the
/// Mac still offers, drawing or not, and is read as an agent's; a new
/// conversation picks none. A Mac that names none and a gglib reached by
/// address are named none.
@MainActor
final class ToolChoiceRunTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private let both = Drawing(
        available: true, model: "flux-dev",
        mcpServers: [OfferedServer(id: 3, name: "tavily"), OfferedServer(id: 9, name: "fs")])

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    private func question(_ model: AppModel) throws -> Message {
        try XCTUnwrap(model.selectedConversation?.messages.last { $0.role == .user })
    }

    /// The servers each run was put naming, in order.
    private func servers(_ hub: FakeRunHub) -> [[Int64]] {
        hub.with { $0.starts.map(\.request.toolServers) }
    }

    private func pick(_ servers: Int64..., in model: AppModel) throws {
        let id = try XCTUnwrap(model.selectedConversationID)
        for server in servers { model.setServer(server, picked: true, for: id) }
    }

    private func ask(_ model: AppModel, _ text: String, draws: Bool = false, until count: Int) async throws {
        XCTAssertTrue(model.send(text, images: [], draws: draws))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == count }
    }

    /// A new conversation's question is a plain run, read as chunks; once
    /// tavily is picked the next is put naming it by id, and read as an
    /// agent's. Nothing goes by the chat route.
    func testANewChatAsksAPlainRunAndAPickedServerIsPutByID() async throws {
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: .offersTavily)
        try await ask(model, "what is new in Swift?", until: 2)
        try pick(3, in: model)
        try await ask(model, "and in cargo?", until: 4)
        XCTAssertEqual(servers(hub), [[], [3]])
        XCTAssertEqual(hub.with(\.readFrames), [.openai, .agent])
        XCTAssertEqual(hub.with { $0.chats.count }, 0)
    }

    /// A Mac with no image model still has its picks named: a message sent
    /// with Draw on goes with them and without drawing, and the question is
    /// not kept as one that drew.
    func testAMacThatCannotDrawStillSendsThePicks() async throws {
        let hub = hub()
        let cannot = Drawing(
            available: false, code: "drawing_unavailable", reason: "there is no image model",
            mcpServers: [OfferedServer(id: 3, name: "tavily")])
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: cannot)
        try pick(3, in: model)
        try await ask(model, "a fox in snow", draws: true, until: 2)
        XCTAssertEqual(servers(hub), [[3]])
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [false])
        XCTAssertEqual(hub.with(\.readFrames), [.agent])
        XCTAssertFalse(try question(model).draws)
    }

    /// A Mac whose answer names no servers, and one from before the list,
    /// are named none of a conversation's picks: a plain question.
    func testAMacThatNamesNoServersIsSentNoneOfThePicks() async throws {
        let none = Drawing(available: true, model: "flux-dev", mcpServers: [])
        for drawing in [none, DrawingRunTests.can] {
            let hub = hub()
            let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: drawing)
            try pick(3, in: model)
            try await ask(model, "what is new in Swift?", until: 2)
            XCTAssertEqual(servers(hub), [[]], String(describing: drawing))
            XCTAssertEqual(hub.with(\.readFrames), [.openai], String(describing: drawing))
        }
    }

    /// Retry asks the question again, naming the picks; Continue carries a
    /// reply's words on, and names none.
    func testRetryNamesThePicksAndContinueDoesNot() async throws {
        let failing = FakeRunHub(frames: [])
        failing.with {
            $0.ending = .failed
            $0.error = RunError(code: "upstream_error", message: "the model stopped answering")
        }
        let (retried, _) = try await DrawingRunTests.makeModel(behind: failing, drawing: .offersTavily)
        try pick(3, in: retried)
        XCTAssertTrue(retried.send("what is new in Swift?", images: []))
        try await Runs.until("the failure") { Runs.settled(retried) && retried.liveReply == nil }
        XCTAssertEqual(retried.selectedConversation?.messages.count, 1)
        try await XCTUnwrap(retried.retry()).value
        XCTAssertEqual(servers(failing), [[3], [3]])
        XCTAssertEqual(failing.with(\.readFrames), [.agent, .agent])

        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: .offersTavily)
        try pick(3, in: model)
        XCTAssertTrue(model.send("what is new in Swift?", images: []))
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        model.stop()
        try await Runs.until("the stop") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).isPartial, true)
        hub.with { $0.holdAt = nil }
        try await XCTUnwrap(model.continueReply()).value
        XCTAssertEqual(servers(hub), [[3], []])
        XCTAssertEqual(hub.with(\.readFrames).last, .openai)
    }

    /// A gglib reached by address is never named a server, whatever it says
    /// of its servers and whatever the conversation picked: only a paired
    /// Mac is.
    func testAGglibByAddressIsNeverSentAServer() async throws {
        let hub = hub()
        let (model, config) = try await Runs.makeModel(behind: hub, direct: true)
        model.drawings[config.id] = .offersTavily
        try pick(3, in: model)
        try await ask(model, "what is new in Swift?", until: 2)
        XCTAssertEqual(servers(hub), [[]])
        XCTAssertEqual(hub.with(\.readFrames), [.openai])
    }

    /// A question whose PUT lost its answer is put again under its id,
    /// built afresh with the conversation's picks as they are then (here
    /// unchanged), and read as an agent's; gglib keeps a started run's
    /// tools.
    func testAQuestionPutAgainAfterItsAnswerWasLostCarriesThePicks() async throws {
        let hub = hub()
        hub.with { $0.putsLost = 1 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = .offersTavily
        try pick(3, in: model)
        try await XCTUnwrap(model.send("go")).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertEqual(servers(hub), [[3], [3]])
        XCTAssertEqual(hub.with(\.readFrames), [.agent])
    }

    /// A Continue whose PUT lost its answer is put again as it was first
    /// sent: with no tools, and read as the chat route's chunks.
    func testAContinuePutAgainAfterItsAnswerWasLostRunsNoTools() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = .offersTavily
        try pick(3, in: model)
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
        XCTAssertEqual(servers(hub), [[3], [], []])
        XCTAssertEqual(hub.with(\.readFrames).last, .openai)
    }

    /// A Continue of a reply that has only thought, to a question that drew,
    /// is put again still ending on that reply when its PUT lost its answer:
    /// with no tools, not drawing, and read as the chat route's chunks. It
    /// is not taken for a run's empty placeholder and dropped, which would
    /// put the question itself again.
    func testAContinueOfAReplyThatOnlyThoughtIsPutAgainAsAContinue() async throws {
        let hub = FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
        hub.with { $0.holdAt = 2 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = .offersTavily
        try pick(3, in: model)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("two thoughts") { model.liveReply?.cursor == 2 }
        model.stop()
        try await Runs.until("the stop") { Runs.settled(model) }
        let partial = try Runs.last(model)
        XCTAssertTrue(partial.isPartial)
        XCTAssertEqual(partial.content, "")
        XCTAssertFalse(partial.reasoning?.isEmpty ?? true)
        XCTAssertTrue(try question(model).draws)
        hub.with {
            $0.holdAt = nil
            $0.putsLost = 1
        }
        try await XCTUnwrap(model.continueReply()).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        let puts = hub.with { $0.starts.map(\.request) }
        guard puts.count == 3 else { return XCTFail("the lost PUT was not sent again") }
        XCTAssertEqual(puts[2].messages.map(\.id), puts[1].messages.map(\.id), "not the Continue that was lost")
        XCTAssertEqual(puts[2].messages.last?.id, partial.id)
        XCTAssertEqual(servers(hub), [[3], [], []])
        XCTAssertEqual(puts.map(\.draws), [true, false, false])
        XCTAssertEqual(hub.with(\.readFrames), [.agent, .openai])
    }

    /// A pick the Mac no longer offers is kept, and not named.
    func testAServerTheMacClosedIsNotNamed() async throws {
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: .offersTavily)
        try pick(3, 9, in: model)
        try await ask(model, "what is new in Swift?", until: 2)
        XCTAssertEqual(servers(hub), [[3]])
        XCTAssertEqual(model.selectedConversation?.toolChoice.picked, [3, 9])
    }

    /// A message sent with Draw and nothing picked is put with `none`, which
    /// leaves it the drawing tool alone, and read as an agent's.
    func testADrawQuestionWithNoPicksIsPutWithNone() async throws {
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: both)
        try await ask(model, "a fox in snow", draws: true, until: 2)
        let put = try XCTUnwrap(hub.with { $0.starts.first?.request })
        XCTAssertEqual(put.toolServers, [])
        XCTAssertEqual(put.toolsWord, "none")
        XCTAssertTrue(put.draws)
        XCTAssertEqual(hub.with(\.readFrames), [.agent])
    }

    /// A pick made while a reply is being written changes nothing of that
    /// run, which was put without it; the next question names it.
    func testAPickMadeDuringARunReachesOnlyTheNextRequest() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: both)
        XCTAssertTrue(model.send("what is new in Swift?", images: []))
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        try pick(9, in: model)
        hub.release()
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }
        try await ask(model, "and in cargo?", until: 4)
        XCTAssertEqual(servers(hub), [[], [9]])
    }

    /// While the Mac has not been heard from, a fresh send names every pick
    /// as kept, for the Mac to narrow to those it opens.
    func testAFreshSendToAnUnheardMacNamesThePicksAsKept() async throws {
        let hub = hub()
        hub.with { $0.drawing = .failure(.transport("not yet")) }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: nil)
        try pick(9, 3, in: model)
        try await ask(model, "what is new in Swift?", until: 2)
        XCTAssertEqual(servers(hub), [[3, 9]])
        XCTAssertEqual(hub.with(\.readFrames), [.agent])
    }

    /// A provider edited to point at another Mac forgets the servers and the
    /// image model each of its conversations chose: an id names a server on
    /// the Mac left alone.
    func testEditingAProviderToAnotherMacForgetsItsChoices() async throws {
        let hub = hub()
        let (model, config) = try await DrawingRunTests.makeModel(behind: hub, drawing: both)
        let id = try XCTUnwrap(model.selectedConversationID)
        try pick(3, in: model)
        model.setTools(on: false, for: id)
        var chosen = try XCTUnwrap(model.selectedConversation)
        chosen.imageModelID = 7
        model.update(chosen)
        var moved = config
        moved.kind = .pipe(ticketDigest: "another-mac")
        model.updateProvider(moved)
        XCTAssertEqual(model.selectedConversation?.toolChoice, ToolChoice())
        XCTAssertNil(model.selectedConversation?.imageModelID)
    }
}
