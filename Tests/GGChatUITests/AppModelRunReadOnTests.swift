import GGChatCore
import XCTest

@testable import GGChatUI

/// When a reply is read on: after a pause when a reading got nothing, a few
/// times and no more; after a `PUT` whose answer was lost, under the same
/// id; and on a return to a hub with no pipe. No log line names the run.
final class AppModelRunReadOnTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    /// A connection that drops before the first event is read on after a
    /// pause, through a pipe and at an address alike.
    @MainActor
    func testADropBeforeTheFirstEventIsReadOnAfterAPause() async throws {
        for direct in [false, true] {
            let hub = hub()
            hub.with { $0.dropAt = 0 }
            let sleeper = ReadOnSleeper(immediate: true)
            let (model, _) = try await Runs.makeModel(behind: hub, sleeper: sleeper, direct: direct)
            try await XCTUnwrap(model.send("go")).value
            try await Runs.until("the reply to be read on") { Runs.settled(model) }
            XCTAssertEqual(try Runs.last(model).content, Runs.text)
            XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 0])
            XCTAssertEqual(sleeper.pauses, [AppModel.readOnDelays[0]])
        }
    }

    /// A hub that never answers is asked a few times, each after a longer
    /// pause, and then left until the next return; the reply stays being
    /// written, with Stop.
    @MainActor
    func testAHubThatNeverAnswersIsNotAskedAgainAndAgain() async throws {
        let hub = hub()
        hub.with { $0.readAnswer = .dropped(.transport("unreachable")) }
        let sleeper = ReadOnSleeper(immediate: true)
        let (model, _) = try await Runs.makeModel(behind: hub, sleeper: sleeper, direct: true)
        try await XCTUnwrap(model.send("go")).value
        let tries = 1 + AppModel.readOnDelays.count
        try await Runs.until("every try") { hub.with { $0.reads.count } == tries }
        for _ in 0..<2_000 { await Task.yield() }
        XCTAssertEqual(hub.with { $0.reads.count }, tries, "the hub was asked again and again")
        XCTAssertEqual(sleeper.pauses, AppModel.readOnDelays)
        XCTAssertTrue(AppModel.readOnDelays.allSatisfy { $0 >= .seconds(1) }, "the tries are not spaced out")
        XCTAssertNotNil(try Runs.last(model).runID)
    }

    /// A `PUT` whose answer was lost keeps its id, and no Retry is offered
    /// beside it. The next reach sends it again under the same id and reads
    /// on from there, so the hub starts one run.
    @MainActor
    func testAPutWhoseAnswerWasLostIsSentAgainUnderItsID() async throws {
        let waiting = hub()
        waiting.with { $0.putsLost = 1 }
        let (held, _) = try await Runs.makeModel(behind: waiting)
        try await XCTUnwrap(held.send("go")).value
        let kept = try Runs.last(held)
        XCTAssertEqual(kept.role, .assistant, "the lost PUT was taken as a failure")
        XCTAssertNotNil(kept.runID)
        XCTAssertNil(kept.runCursor, "a run never confirmed kept a cursor")
        XCTAssertNil(held.retry(), "Retry would start a second run")

        let hub = hub()
        hub.with { $0.putsLost = 1 }
        let (model, _) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        try await XCTUnwrap(model.send("go")).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        let ids = hub.with { $0.starts.map(\.id) }
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 1, "the PUT was sent again under a new id")
        XCTAssertEqual(
            hub.with { $0.starts.map(\.request.messages) }.last, hub.with { $0.starts.first?.request.messages },
            "the PUT sent again was not the one sent first")
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0])
    }

    /// A return reads on at an address with no pipe, which no pipe coming up
    /// would ever have asked for.
    @MainActor
    func testAReturnReadsOnAtAnAddressWithNoPipe() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 3 }
        let (model, _) = try await Runs.makeModel(behind: hub, direct: true)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("three frames") { model.liveReply?.cursor == 3 }
        await model.scene(.background).value
        await task.value
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 3])
    }

    /// Across starting, walking away, reading on, a refusal, a failed cancel
    /// and a hub without runs, no log line carries a run's id, a word of the
    /// reply, or an address.
    @MainActor
    func testNoLogLineNamesARunItsTextOrAnAddress() async throws {
        let log = CapturingLogSink()
        let hub = hub()
        hub.with { $0.holdAt = 3 }
        hub.with { $0.cancelFails = true }
        let (model, _) = try await Runs.makeModel(behind: hub, log: log, direct: true)
        let first = try XCTUnwrap(model.send("go"))
        try await Runs.until("three frames") { model.liveReply?.cursor == 3 }
        await model.scene(.background).value
        await first.value
        hub.with { $0.readAnswer = .refused(.server(status: 401, code: "invalid_api_key", message: "no")) }
        await model.scene(.foreground).value
        try await Runs.until("the run to be given up") { Runs.settled(model) }
        hub.with { $0.readAnswer = nil }
        let second = try XCTUnwrap(model.send("again"))
        try await Runs.until("three more frames") { model.liveReply?.cursor == 3 }
        model.stop()
        await second.value
        hub.with { $0.start = .unsupported }
        try await XCTUnwrap(model.send("once more")).value

        let ids = hub.with { $0.starts.map(\.id) }
        XCTAssertEqual(ids.count, 3)
        XCTAssertGreaterThan(log.lines.count, 2, "the app does log, so an empty log would prove nothing")
        let words = ["reads", "longest", "short", "http", "127.0.0.1", "/v1"]
        for line in log.lines {
            for forbidden in ids + words {
                XCTAssertFalse(line.contains(forbidden), "\(forbidden) in a log line: \(line)")
            }
        }
    }
}
