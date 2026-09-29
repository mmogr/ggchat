import GGChatCore
import XCTest

@testable import GGChatUI

/// No reply stays "still being written" with no way out: a hub that refuses
/// gives the run up, one that cannot be reached is waited for with Stop
/// offered, and removing the provider gives its runs up.
final class AppModelRunWayOutTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    /// Sends, lets `frames` of the reply arrive, and goes to the background.
    @MainActor
    private func detach(after frames: UInt32, from hub: FakeRunHub) async throws -> AppModel {
        hub.with { $0.holdAt = frames }
        let (model, _) = try await Runs.makeModel(behind: hub)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("\(frames) frames") { hub.with { !$0.reads.isEmpty } && model.liveReply?.cursor == frames }
        await model.scene(.background).value
        await task.value
        return model
    }

    /// A 401 or a 403 on the events route is a refusal asking again would
    /// repeat: the run is given up, what arrived keeps Continue under a
    /// sentence that says why, and an empty reply leaves the question with
    /// Retry.
    @MainActor
    func testARefusalOfTheEventsGivesTheRunUpWithASentence() async throws {
        let refusals: [(frames: UInt32, error: ProviderError)] = [
            (5, .server(status: 401, code: "invalid_api_key", message: "invalid or missing bearer token")),
            (0, .server(status: 403, code: "not_yours", message: "this run belongs to another device")),
        ]
        for refusal in refusals {
            let hub = hub()
            let model = try await detach(after: refusal.frames, from: hub)
            hub.with { $0.readAnswer = .refused(refusal.error) }
            await model.scene(.foreground).value
            try await Runs.until("the run to be given up") { Runs.settled(model) }
            let last = try Runs.last(model)
            let sentence = "home would not send the rest of this reply. \(refusal.error.errorDescription ?? "")"
            XCTAssertEqual(last.failure?.message, sentence)
            XCTAssertEqual(last.failure?.code, refusal.error.code)
            if refusal.frames == 0 {
                XCTAssertEqual(last.role, .user)
                XCTAssertNotNil(model.retry(), "the question offers no Retry")
            } else {
                XCTAssertEqual(last.content, "It reads ")
                XCTAssertTrue(last.isPartial)
                XCTAssertNotNil(model.continueReply(), "the partial offers no Continue")
            }
        }
    }

    /// A hub that answers 5xx is waited for: the reply stays being written.
    /// Stop gets out of it whether or not the hub can be reached, cancelling
    /// the run when it can, and leaves the partial with Continue.
    @MainActor
    func testAnUnreachableHubIsWaitedForAndStopAlwaysGetsOut() async throws {
        for reachable in [true, false] {
            let hub = hub()
            let model = try await detach(after: 5, from: hub)
            hub.with { $0.readAnswer = .dropped(.server(status: 502, code: "tunnel_unavailable", message: "no")) }
            await model.scene(.foreground).value
            try await Runs.until("the hub to be asked") { hub.with { $0.reads.count } == 2 && model.liveReply == nil }
            let waiting = try Runs.last(model)
            XCTAssertNotNil(waiting.runID, "a 5xx gave the run up")
            if !reachable { await model.scene(.background).value }

            model.stopWriting(waiting.id)

            let stopped = try Runs.last(model)
            XCTAssertNil(stopped.runID, "Stop left the reply still being written")
            XCTAssertTrue(stopped.isPartial)
            XCTAssertNil(stopped.failure)
            XCTAssertEqual(stopped.content, "It reads ")
            if reachable {
                try await Runs.until("the run to be cancelled") { !hub.with { $0.cancels.isEmpty } }
                XCTAssertEqual(hub.with { $0.cancels }, [waiting.runID].compactMap { $0 })
                XCTAssertNotNil(model.continueReply(), "the partial offers no Continue")
            } else {
                XCTAssertEqual(hub.with { $0.cancels }, [], "a cancel went to a hub that cannot be reached")
            }
        }
    }

    /// Removing the provider gives up the runs still writing replies through
    /// it, cancelling them first while its hub can be reached.
    @MainActor
    func testRemovingTheProviderGivesUpItsRuns() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 5 }
        let (model, config) = try await Runs.makeModel(behind: hub)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("five frames") { model.liveReply?.cursor == 5 }
        // Walked away from as the background does, with the pipe left up.
        model.liveReply?.detaching = true
        model.stop()
        await task.value
        let waiting = try Runs.last(model)
        XCTAssertNotNil(waiting.runID)

        model.removeProvider(config.id)

        let given = try Runs.last(model)
        XCTAssertNil(given.runID, "a removed provider's reply stayed being written")
        XCTAssertTrue(given.isPartial)
        XCTAssertEqual(given.content, "It reads ")
        try await Runs.until("the run to be cancelled") { !hub.with { $0.cancels.isEmpty } }
        XCTAssertEqual(hub.with { $0.cancels }, [waiting.runID].compactMap { $0 })
    }
}
