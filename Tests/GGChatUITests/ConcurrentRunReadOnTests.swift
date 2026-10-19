import GGChatCore
import XCTest

@testable import GGChatUI

/// Replies a hub went on writing in two conversations while the app was
/// away are both read on when it comes back, not one after the other
/// (ADR 0012).
final class ConcurrentRunReadOnTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    @MainActor
    func testTwoDetachedRunsAreBothReadOnAfterAReturn() async throws {
        let hub = FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
        hub.with { $0.holdAt = 3 }
        let (model, _) = try await Runs.makeModel(behind: hub, direct: true)
        let first = try XCTUnwrap(model.selectedConversationID)
        let firstTask = try XCTUnwrap(model.send("go"))
        try await Runs.until("three frames in the first") { model.liveReplies[first]?.cursor == 3 }
        let second = model.newConversation().id
        let secondTask = try XCTUnwrap(model.send("go"), "the second send waited on the first reply")
        try await Runs.until("three frames in the second") { model.liveReplies[second]?.cursor == 3 }

        await model.scene(.background).value
        await firstTask.value
        await secondTask.value
        // Still held, so a reply read on is not finished yet: read one at a
        // time, the second would never start.
        await model.scene(.foreground).value
        try await Runs.until("both replies to be read on at once") {
            model.liveReplies.count == 2 && hub.with { $0.reads.filter { $0.after == 3 }.count } == 2
        }
        hub.release()

        try await Runs.until("both replies to end") {
            model.liveReplies.isEmpty && !model.conversations.contains { $0.messages.contains(where: \.isBeingWritten) }
        }
        for id in [first, second] {
            XCTAssertEqual(model.conversations.first { $0.id == id }?.messages.last?.content, Runs.text)
        }
    }
}
