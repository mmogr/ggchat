import GGChatCore
import XCTest

@testable import GGChatUI

/// The look at a picture being drawn, on the reply that waits for it: the
/// latest one only, in memory, gone when its tool ends or its run does, and
/// never a step of the run's cursor.
@MainActor
final class DrawingPreviewTests: XCTestCase {
    private func look(_ step: Int, call: String = "c1") -> PreviewFrame {
        PreviewFrame(callID: call, step: step, total: 20, data: Data([UInt8(step)]))
    }

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// Only the latest look is held, and it goes when its own tool's call
    /// ends, not another's, and when the run ends.
    func testOnlyTheLatestLookIsHeldAndItGoesWithItsTool() {
        var work = ToolWork()
        work.show(look(3))
        XCTAssertFalse(work.isEmpty)
        work.show(look(4))
        XCTAssertEqual(work.preview, look(4))
        work.apply(.delta("words beside it"))
        work.apply(.toolEnded("another"))
        XCTAssertEqual(work.preview, look(4), "another tool's end dropped the look")
        work.apply(.toolEnded("c1"))
        XCTAssertNil(work.preview, "a look outlived its tool")
        XCTAssertTrue(work.isEmpty)

        work.show(look(5))
        work.end()
        XCTAssertNil(work.preview)
    }

    /// A Mac's reply shows the look its run sends beside its frames. The
    /// cursor stays at the last frame, so reading on asks from there, and
    /// the look is gone once the tool that drew it has finished.
    func testAMacsReplyShowsTheLookAndItsCursorDoesNotMove() async throws {
        let image = ImageRef(id: "a1", mime: ImageRef.png, width: 1024, height: 1024)
        let step = ToolProgress(callID: "c1", stage: .sampling, pass: 1, done: 4, total: 20)
        let hub = FakeChatsHub(reply: [
            [.tool("Generate Image")], [.toolProgress(step)], [.toolEnded("c1"), .images([image])], [.delta("A fox.")],
        ])
        hub.runs.with {
            $0.holdAt = 2
            $0.previews = [2: look(4)]
        }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat("a fox in snow")
        try await until("the look") { model.openHubReply?.work.preview != nil }
        let reply = try XCTUnwrap(model.openHubReply)
        XCTAssertEqual(reply.work.preview, look(4))
        XCTAssertEqual(reply.cursor, 2, "a look moved the cursor")

        await model.scene(.background).value
        XCTAssertEqual(reply.work.preview, look(4), "walking away dropped the look")
        hub.runs.with { $0.previews = [:] }
        await model.scene(.foreground).value
        try await until("the second read") { hub.runs.with(\.reads).count == 2 }
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0, 2])

        hub.runs.release()
        try await until("the end") { reply.ended }
        XCTAssertNil(reply.work.preview)
        XCTAssertEqual(reply.made, [image])
    }

    /// A run that ends in the middle of a picture leaves no look behind.
    func testARunThatEndsMidPictureLeavesNoLook() async throws {
        let hub = FakeChatsHub(reply: [[.tool("Generate Image")]])
        hub.runs.with {
            $0.holdAt = 1
            $0.previews = [1: look(2)]
            $0.ending = .cancelled
        }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat("a fox in snow")
        try await until("the look") { model.openHubReply?.work.preview != nil }
        let reply = try XCTUnwrap(model.openHubReply)
        hub.runs.release()
        try await until("the end") { reply.ended }
        XCTAssertNil(reply.work.preview, "a run that ended left a look on its reply")
    }
}
