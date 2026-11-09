import XCTest

@testable import GGChatCore

/// Replays the run bodies gglib records (`contracts/runs/recorded.json` there,
/// copied here as a fixture) against the Swift run types, and its
/// `tool_reply` frames against how an agent run's events are read. The copy
/// is from gglib's `test(contracts): a tool result with images is recorded`,
/// in the change that adds a tool's images to its result; the copy now is
/// of gglib's 6b3f9d44 (`feat(gui)/chat-without-lock`), which records a
/// run's `frames`, `model_load`, the wait while its model loads, and
/// `image_render`, the wait behind a picture, each with the sentence it is
/// shown as, `said`.
final class RunsWireTests: XCTestCase {
    private struct Recorded: Decodable {
        let queued: RunInfo
        let inProgress: RunInfo
        let completed: RunInfo
        let failed: RunInfo
        let cancelled: RunInfo
        let list: RunList

        enum CodingKeys: String, CodingKey {
            case queued
            case inProgress = "in_progress"
            case completed
            case failed
            case cancelled
            case list
        }
    }

    private static let created: UInt64 = 1_790_000_000_000

    private func recorded() throws -> Recorded {
        try JSONDecoder().decode(Recorded.self, from: try Fixtures.data("gglib-runs-recorded.json"))
    }

    func testQueuedRunHasOnlyItsRequiredFields() throws {
        let run = try recorded().queued
        let want = RunInfo(id: "run-queued-01", kind: .chat, status: .queued, createdAtMs: Self.created, lastSeq: 0)
        XCTAssertEqual(run, want)
    }

    /// An agent run says its frames are written as an agent's events.
    func testInProgressRunCarriesModelDeviceAndSeq() throws {
        let want = RunInfo(
            id: "run-busy-02", kind: .agent, status: .inProgress, model: "qwen3-8b", device: "phone-7c2e",
            createdAtMs: Self.created, lastSeq: 42, frames: .agent)
        XCTAssertEqual(try recorded().inProgress, want)
    }

    func testCompletedRunCarriesItsFinishTime() throws {
        let want = RunInfo(
            id: "run-done-03", kind: .chat, status: .completed, model: "qwen3-8b",
            createdAtMs: Self.created, finishedAtMs: Self.created + 8_250, lastSeq: 311)
        XCTAssertEqual(try recorded().completed, want)
    }

    func testFailedRunCarriesItsError() throws {
        let want = RunInfo(
            id: "run-failed-04", kind: .agent, status: .failed, model: "gemma-3-12b", device: "phone-7c2e",
            createdAtMs: Self.created, finishedAtMs: Self.created + 1_500, lastSeq: 3,
            error: RunError(code: "model_unavailable", message: "The model could not be loaded."), frames: .agent)
        XCTAssertEqual(try recorded().failed, want)
    }

    func testCancelledRunCarriesItsFinishTime() throws {
        let want = RunInfo(
            id: "run-cancelled-05", kind: .chat, status: .cancelled,
            createdAtMs: Self.created, finishedAtMs: Self.created + 600, lastSeq: 7)
        XCTAssertEqual(try recorded().cancelled, want)
    }

    func testListHoldsTheRunsInOrder() throws {
        let body = try recorded()
        XCTAssertEqual(body.list, RunList(runs: [body.inProgress, body.failed]))
    }

    func testNullOptionalsDecodeAsNil() throws {
        let json = """
            {"id": "r", "kind": "chat", "status": "queued", "created_at_ms": 1, "last_seq": 0,
             "model": null, "device": null, "finished_at_ms": null, "error": null}
            """
        let run = try JSONDecoder().decode(RunInfo.self, from: Data(json.utf8))
        XCTAssertEqual(run, RunInfo(id: "r", kind: .chat, status: .queued, createdAtMs: 1, lastSeq: 0))
    }

    func testNilOptionalsAreLeftOutWhenEncoded() throws {
        let run = RunInfo(id: "r", kind: .chat, status: .queued, createdAtMs: 1, lastSeq: 0)
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(run))
        let keys = try XCTUnwrap(object as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["created_at_ms", "id", "kind", "last_seq", "status"])
    }

    /// The recorded reply whose tool made one image reads as its tool line
    /// and its call, the end of that call and its answer, that image with its id, type and size, and its
    /// text.
    func testARecordedToolReplyReadsAsItsToolLineItsImageAndItsText() throws {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-runs-recorded.json"))
        let frames = try XCTUnwrap((object as? [String: Any])?["tool_reply"] as? [Any])
        let events = try frames.flatMap { frame in
            let data = try JSONSerialization.data(withJSONObject: frame)
            return OpenAICompatibleProvider.agentEvents(SSEEvent(data: String(decoding: data, as: UTF8.self)))
        }
        let image = ImageRef(
            id: "ece5c33be7ce69ce71231b9d81671f4de1c35ee51fc684b014da4eb244e9a8ae", mime: "image/png", width: 1024,
            height: 1024)
        XCTAssertEqual(
            events,
            [
                .tool("Draw"),
                .toolCalled(ToolExchange(callID: "call-draw-1", name: "draw", arguments: #"{"prompt":"a red dot"}"#)),
                .toolEnded("call-draw-1"),
                .toolAnswered(callID: "call-draw-1", text: "[image 1024x1024 PNG stored]", failed: false),
                .images([image], callID: "call-draw-1"), .delta("Here is a red dot."),
            ])
    }

    /// The events one recorded frame reads as.
    private func recordedEvents(_ key: String) throws -> [ChatEvent] {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-runs-recorded.json"))
        let frame = try XCTUnwrap((object as? [String: Any])?[key], "gglib recorded no \(key)")
        let data = try JSONSerialization.data(withJSONObject: frame)
        return OpenAICompatibleProvider.agentEvents(SSEEvent(data: String(decoding: data, as: UTF8.self)))
    }

    /// The recorded wait while a run's model loads names the model as the
    /// catalogue shows it, how long the load has taken, and the sentence
    /// gglib shows it as.
    func testTheRecordedLoadWaitNamesItsModelAndItsTime() throws {
        XCTAssertEqual(
            try recordedEvents("model_load"),
            [
                .waiting(
                    RunWait(
                        reason: .modelLoad, model: "Qwen3-4B", elapsedMS: 1000, said: "Loading Qwen3-4B\u{2026} 1 s"))
            ])
    }

    /// The recorded wait behind a picture says the step it is at, its place
    /// in line and the sentence gglib shows it as.
    func testTheRecordedRenderWaitSaysItsStepItsPlaceAndItsSentence() throws {
        XCTAssertEqual(
            try recordedEvents("image_render"),
            [
                .waiting(
                    RunWait(
                        reason: .imageRender, step: 3, total: 20, position: 2,
                        said: "Waiting for an image render, step 3 of 20, 2 in line"))
            ])
    }

    func testOnlyCompletedFailedAndCancelledAreTerminal() {
        XCTAssertFalse(RunStatus.queued.isTerminal)
        XCTAssertFalse(RunStatus.inProgress.isTerminal)
        XCTAssertTrue(RunStatus.completed.isTerminal)
        XCTAssertTrue(RunStatus.failed.isTerminal)
        XCTAssertTrue(RunStatus.cancelled.isTerminal)
    }
}
