import GGChatCore
import XCTest

@testable import GGChatUI

/// Drawing a second time in one chat: Draw can be pressed again once the
/// first picture's reply has ended, and the second picture's steps and the
/// looks at it reach the reply as the first's did, in both kinds of chat.
@MainActor
final class DrawAgainTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private static let png = Data("A PICTURE OF A FOX".utf8)
    private static let image = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 1024, height: 1024)
    private static let look = PreviewFrame(callID: "c1", step: 4, total: 20, data: Data("A BLURRED FOX".utf8))
    private static let step = ToolProgress(callID: "c1", stage: .sampling, pass: 1, done: 4, total: 20)
    /// A run that calls the tool, draws `image` and says a word.
    private static let frames: [[ChatEvent]] = [
        [.tool("Generate Image")], [.toolProgress(step)], [.toolEnded("c1"), .images([image], callID: "c1")],
        [.delta("A fox.")],
    ]

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await Runs.until(what, condition)
    }

    /// A press that changes only the switch is a change to the draft. Both
    /// composers hold their draft as SwiftUI state, and SwiftUI asks the
    /// draft's own `==` whether a write changed it: answered "the same", the
    /// press was kept and the composer not drawn again, so after a first
    /// message Draw looked off however often it was pressed, until
    /// something else redrew the composer. A composer with nothing in it
    /// but the switch is still empty.
    func testAPressOfDrawAloneIsAChangeToTheDraft() {
        XCTAssertNotEqual(Draft(text: "and at night"), Draft(text: "and at night", draws: true))
        XCTAssertNotEqual(Draft(), Draft(draws: true))
        XCTAssertEqual(Draft(text: "and at night", draws: true), Draft(text: "and at night", draws: true))
        XCTAssertTrue(Draft(draws: true).isEmpty)
        XCTAssertFalse(Draft(text: " ").isEmpty)
    }

    /// A conversation kept on this phone, drawn in twice. Once the first
    /// reply has ended nothing refuses Draw and the conversation takes a
    /// turn; the draft the send left has the switch off, and pressing it
    /// again is sent; and the second run's step and look reach its reply.
    func testAConversationHereDrawsASecondTime() async throws {
        let hub = FakeRunHub(frames: Self.frames)
        hub.with {
            $0.images[Self.image.id] = Self.png
            $0.previews = [2: Self.look]
        }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub)
        var draft = Draft(text: "a fox in snow", draws: true)
        draft.send(through: model)
        try await until("the first reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }

        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertNil(model.drawRefusal(for: conversation), "Draw was refused after a picture")
        XCTAssertTrue(model.takesTurn(conversation))
        XCTAssertFalse(model.isStreaming(conversation.id))
        XCTAssertFalse(draft.draws)

        hub.with { $0.holdAt = 2 }
        draft.text = "and at night"
        draft.draws = true
        draft.send(through: model)
        try await until("the second look") { model.liveReply?.work.preview != nil }
        let live = try XCTUnwrap(model.liveReply)
        XCTAssertEqual(live.work.progress, Self.step)
        XCTAssertEqual(live.work.preview, Self.look)
        XCTAssertEqual(live.tools, ["Generate Image"])
        XCTAssertEqual(live.cursor, 2)
        XCTAssertEqual(hub.with { $0.starts.map(\.request.draws) }, [true, true])
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 0], "the second run was read from the first's cursor")
        XCTAssertEqual(hub.with(\.readFrames), [.agent, .agent])
        XCTAssertNotEqual(hub.with { $0.starts[0].id }, hub.with { $0.starts[1].id })

        hub.release()
        try await until("the second reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 4 }
        XCTAssertEqual(try Runs.last(model).images, [Self.image])
        XCTAssertNil(model.drawRefusal(for: try XCTUnwrap(model.selectedConversation)))
    }

    /// A Mac's chat, drawn in twice: the same, on the turn's own path.
    func testAMacsChatDrawsASecondTime() async throws {
        let hub = FakeChatsHub(reply: Self.frames)
        hub.runs.with {
            $0.drawing = .success(Drawing(available: true, model: "flux-dev"))
            $0.previews = [2: Self.look]
        }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        try await until("the ask") { hub.runs.with(\.drawingAsked) > 0 && model.opening[config.id] == nil }
        await model.catchUp(config.id, quietly: true)
        var draft = Draft(text: "a fox in snow", draws: true)
        draft.sendToHubChat(through: model)
        try await until("the first reply's end") { model.hubReplies.isEmpty }

        XCTAssertNil(model.hubDrawRefusal, "Draw was refused after a picture")
        XCTAssertFalse(model.openHubChatIsWriting)
        XCTAssertFalse(draft.draws)

        hub.runs.with { $0.holdAt = 2 }
        draft.text = "and at night"
        draft.draws = true
        draft.sendToHubChat(through: model)
        try await until("the second look") { model.openHubReply?.work.preview != nil }
        let reply = try XCTUnwrap(model.openHubReply)
        XCTAssertEqual(reply.work.progress, Self.step)
        XCTAssertEqual(reply.work.preview, Self.look)
        XCTAssertEqual(reply.tools, ["Generate Image"])
        XCTAssertEqual(reply.cursor, 2)
        XCTAssertEqual(hub.with { $0.turns.map(\.turn.draw) }, [true, true])
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0, 0])

        hub.runs.release()
        try await until("the second reply's end") { model.hubReplies.isEmpty }
        XCTAssertNil(model.hubDrawRefusal)
    }
}
