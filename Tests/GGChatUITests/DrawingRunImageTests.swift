import GGChatCore
import XCTest

@testable import GGChatUI

/// The picture a run drew for a conversation kept on this phone: read from
/// the hub once, kept in this phone's own store under its id, named by the
/// reply, and asked for again when it was lost on the way.
@MainActor
final class DrawingRunImageTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private static let png = Data("A PICTURE OF A FOX".utf8)
    private static let image = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 1024, height: 1024)
    private static let look = PreviewFrame(callID: "c1", step: 4, total: 20, data: Data("A BLURRED FOX".utf8))
    private static let step = ToolProgress(callID: "c1", stage: .sampling, pass: 1, done: 4, total: 20)

    /// A hub whose every run calls the tool, draws `image` and says a word.
    private func hub(holding: Bool = true) -> FakeRunHub {
        let hub = FakeRunHub(frames: [
            [.tool("Generate Image")], [.toolProgress(Self.step)], [.toolEnded("c1"), .images([Self.image])],
            [.delta("A fox.")],
        ])
        hub.with {
            if holding { $0.images[Self.image.id] = Self.png }
            $0.previews = [2: Self.look]
        }
        return hub
    }

    private func draw(_ model: AppModel, _ text: String = "a fox in snow") {
        XCTAssertTrue(model.send(text, images: [], draws: true))
    }

    /// While the picture is drawn the reply shows its step and the latest
    /// look, and its cursor is the last frame's. Once it is done its bytes
    /// are in this phone's store under their SHA-256, the reply's message
    /// names it, and neither the look nor the step is kept anywhere. The
    /// same picture drawn again is not read from the hub a second time.
    func testAPictureIsReadOnceAndKeptUnderItsID() async throws {
        let store = InMemoryStore()
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, store: store)
        draw(model)
        try await Runs.until("the look") { model.liveReply?.work.preview != nil }
        let live = try XCTUnwrap(model.liveReply)
        XCTAssertEqual(live.work.preview, Self.look)
        XCTAssertEqual(live.work.progress, Self.step)
        XCTAssertEqual(live.cursor, 2, "a look moved the cursor")
        XCTAssertEqual(hub.with(\.fetches), [], "the picture was read before its tool finished")

        hub.release()
        try await Runs.until("the reply") { Runs.settled(model) }
        let reply = try Runs.last(model)
        XCTAssertEqual(reply.content, "A fox.")
        XCTAssertEqual(reply.images, [Self.image])
        XCTAssertFalse(reply.isPartial)
        XCTAssertNil(reply.runFrames)
        XCTAssertEqual(try store.loadImage(id: Self.image.id), Self.png)
        XCTAssertEqual(hub.with(\.fetches), [Self.image.id])
        XCTAssertNil(try store.loadImage(id: ImageRef.id(of: Self.look.data)), "a look was kept")
        XCTAssertEqual(try store.loadConversations().first?.messages.last?.images, [Self.image])

        draw(model, "the same again")
        try await Runs.until("the second reply") {
            Runs.settled(model) && model.selectedConversation?.messages.count == 4
        }
        XCTAssertEqual(try Runs.last(model).images, [Self.image])
        XCTAssertEqual(hub.with(\.fetches), [Self.image.id], "a picture already kept was read again")
    }

    /// A picture lost on the way is not passed over: the frame that names
    /// it is not applied, the reply walks away with its cursor at the frame
    /// before and the run's decoder kept with it, and the next reading asks
    /// for the picture again and keeps it.
    func testAPictureLostOnTheWayIsAskedForAgain() async throws {
        let store = InMemoryStore()
        let hub = hub()
        hub.with { $0.fetchFailures = [.dropped(.transport("the connection dropped"))] }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, store: store)
        draw(model)
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 2])
        XCTAssertEqual(hub.with(\.readFrames), [.agent, .agent])
        XCTAssertEqual(hub.with(\.fetches), [Self.image.id, Self.image.id])
        XCTAssertEqual(try Runs.last(model).images, [Self.image])
        XCTAssertEqual(try Runs.last(model).content, "A fox.")
        XCTAssertEqual(try store.loadImage(id: Self.image.id), Self.png)
        XCTAssertEqual(hub.with(\.cancels), [])
    }

    /// A picture the hub no longer has, and one whose bytes are not the
    /// ones its id names, are named by the reply and not kept. The reply is
    /// still whole, and the next message is sent without them: a reply's
    /// picture is never part of a request.
    func testAPictureTheHubDoesNotHaveIsNamedAndNotKept() async throws {
        for wrongBytes in [false, true] {
            let store = InMemoryStore()
            let hub = hub(holding: false)
            if wrongBytes { hub.with { $0.images[Self.image.id] = Data("another picture".utf8) } }
            let (model, _) = try await DrawingRunTests.makeModel(behind: hub, store: store)
            draw(model)
            try await Runs.until("the reply") { Runs.settled(model) }
            XCTAssertEqual(try Runs.last(model).images, [Self.image])
            XCTAssertEqual(try Runs.last(model).content, "A fox.")
            XCTAssertNil(try store.loadImage(id: Self.image.id))
            XCTAssertEqual(hub.with(\.fetches), [Self.image.id])

            XCTAssertTrue(model.send("and what is a fox?", images: []))
            try await Runs.until("the next reply") {
                Runs.settled(model) && model.selectedConversation?.messages.count == 4
            }
            XCTAssertNil(model.lastError)
            XCTAssertEqual(hub.with { $0.starts.last?.request.images }, [:])
        }
    }

    /// The background walks away from a picture being drawn: the reply's
    /// message keeps its run, its cursor and how the run writes its events,
    /// in the store, and coming back reads on from there as an agent's. A
    /// reply that draws nothing keeps no such word and is read as chunks.
    func testAReplyReadOnIsReadAsItsRunWritesIt() async throws {
        let store = InMemoryStore()
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, store: store)
        draw(model)
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        await model.scene(.background).value
        let kept = try XCTUnwrap(try store.loadConversations().first?.messages.last)
        XCTAssertNotNil(kept.runID)
        XCTAssertEqual(kept.runCursor, 2)
        XCTAssertEqual(kept.runFrames, .agent)

        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 2])
        XCTAssertEqual(hub.with(\.readFrames), [.agent, .agent])
        XCTAssertEqual(try Runs.last(model).images, [Self.image])
        XCTAssertNil(try Runs.last(model).runFrames)

        let plain = FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
        plain.with { $0.holdAt = 2 }
        let (other, _) = try await DrawingRunTests.makeModel(behind: plain, store: InMemoryStore())
        XCTAssertTrue(other.send("go", images: []))
        try await Runs.until("two frames") { other.liveReply?.cursor == 2 }
        await other.scene(.background).value
        XCTAssertNil(try Runs.last(other).runFrames)
        plain.with { $0.holdAt = nil }
        await other.scene(.foreground).value
        try await Runs.until("the reply") { Runs.settled(other) }
        XCTAssertEqual(plain.with(\.readFrames), [.openai, .openai])
    }

    /// A reply stopped once its picture is drawn and before any word is
    /// kept, with its picture, whether it was read in one go or walked away
    /// from before the picture came.
    func testAReplyOfAPictureAloneIsKept() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 3 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub)
        draw(model)
        try await Runs.until("the picture") { model.liveReply?.made == [Self.image] }
        model.stop()
        try await Runs.until("the stop") { Runs.settled(model) }
        let reply = try Runs.last(model)
        XCTAssertEqual(reply.role, .assistant)
        XCTAssertEqual(reply.content, "")
        XCTAssertEqual(reply.images, [Self.image])

        let later = self.hub()
        later.with { $0.holdAt = 2 }
        let (other, _) = try await DrawingRunTests.makeModel(behind: later)
        draw(other)
        try await Runs.until("two frames") { other.liveReply?.cursor == 2 }
        await other.scene(.background).value
        later.with { $0.holdAt = 3 }
        await other.scene(.foreground).value
        try await Runs.until("the picture") { other.liveReply?.made == [Self.image] }
        other.stop()
        try await Runs.until("the stop") { Runs.settled(other) }
        XCTAssertEqual(try Runs.last(other).role, .assistant)
        XCTAssertEqual(try Runs.last(other).images, [Self.image])
    }
}
