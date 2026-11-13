import GGChatCore
import XCTest

@testable import GGChatUI

/// What a reply being written shows of a picture being drawn and of a wait
/// for something else: the latest word, one line for it, and nothing once
/// the tool or the run has ended.
@MainActor
final class ToolWorkTests: XCTestCase {
    private static let british = Locale(identifier: "en_GB")

    private func progress(
        _ stage: ToolProgress.Stage, call: String = "c1", pass: Int? = nil, done: Int? = nil, total: Int? = nil,
        position: Int? = nil
    ) -> ToolProgress {
        ToolProgress(callID: call, stage: stage, pass: pass, done: done, total: total, position: position)
    }

    /// Each stage of a picture has its line, with the step in the locale's
    /// digits, the picture's number from the second on, and the place in
    /// line when it is not next.
    func testEachStageOfAPictureHasItsLine() {
        func line(_ progress: ToolProgress, _ locale: Locale = Self.british) -> String {
            ToolWork.line(for: progress, in: locale)
        }
        XCTAssertEqual(line(progress(.queued, position: 1)), "Drawing: waiting in line")
        XCTAssertEqual(line(progress(.queued, position: 3)), "Drawing: waiting in line, place 3")
        XCTAssertEqual(line(progress(.queued)), "Drawing: waiting in line")
        XCTAssertEqual(line(progress(.loading)), "Drawing: loading the image model")
        XCTAssertEqual(line(progress(.sampling, pass: 1, done: 12, total: 20)), "Drawing: step 12 of 20")
        XCTAssertEqual(line(progress(.sampling, pass: 2, done: 3, total: 20)), "Drawing picture 2: step 3 of 20")
        XCTAssertEqual(line(progress(.sampling)), "Drawing")
        XCTAssertEqual(line(progress(.decoding)), "Drawing: finishing the picture")
        XCTAssertEqual(line(progress(.finishing)), "Drawing: saving the picture")
        XCTAssertEqual(
            line(progress(.sampling, done: 12, total: 20), Locale(identifier: "ar_EG")),
            "Drawing: step \u{0661}\u{0662} of \u{0662}\u{0660}")
    }

    /// A wait says what is in the way, how far that has got when it is
    /// known, and the place in line when it is not next. A load is said in
    /// gglib's words (`waiting_sentence`): the model by name, or "the
    /// model", and the whole seconds from one on, in the locale's digits.
    func testAWaitSaysWhatIsInTheWay() {
        func line(_ wait: RunWait, _ locale: Locale = Self.british) -> String { ToolWork.line(for: wait, in: locale) }
        XCTAssertEqual(
            line(RunWait(reason: .imageRender, step: 12, total: 20, position: 1)),
            "Waiting for a picture to be drawn, at step 12 of 20")
        XCTAssertEqual(line(RunWait(reason: .imageRender)), "Waiting for a picture to be drawn")
        XCTAssertEqual(
            line(RunWait(reason: .imageRender, step: 2, total: 20, position: 2)),
            "Waiting for a picture to be drawn, at step 2 of 20, place 2 in line")
        XCTAssertEqual(line(RunWait(reason: .modelLoad)), "Loading the model\u{2026}")
        XCTAssertEqual(line(RunWait(reason: .modelLoad, position: 3)), "Loading the model\u{2026}")
        XCTAssertEqual(
            line(RunWait(reason: .modelLoad, model: "Qwen3-4B", elapsedMS: 12_900)), "Loading Qwen3-4B\u{2026} 12 s")
        XCTAssertEqual(line(RunWait(reason: .modelLoad, model: "Qwen3-4B", elapsedMS: 999)), "Loading Qwen3-4B\u{2026}")
        XCTAssertEqual(line(RunWait(reason: .modelLoad, model: "Qwen3-4B", elapsedMS: 0)), "Loading Qwen3-4B\u{2026}")
        XCTAssertEqual(line(RunWait(reason: .modelLoad, elapsedMS: 3_000)), "Loading the model\u{2026} 3 s")
        // Plain digits, ungrouped, as gglib prints them, whatever the locale.
        XCTAssertEqual(
            line(RunWait(reason: .modelLoad, model: "Qwen3-4B", elapsedMS: 12_000), Locale(identifier: "ar_EG")),
            "Loading Qwen3-4B\u{2026} 12 s")
        XCTAssertEqual(line(RunWait(reason: .modelLoad, elapsedMS: 1_234_000)), "Loading the model\u{2026} 1234 s")
    }

    /// One of gglib's recorded `waiting` frames, from the fixture the core
    /// tests read, found beside this file's package, without `said` when
    /// `said` is false, as a gglib before 0.31.0 sends it.
    private static func recordedWait(_ key: String, said: Bool = true) throws -> RunWait {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "GGChatCoreTests/Fixtures/gglib-runs-recorded.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        var frame = try XCTUnwrap((object as? [String: Any])?[key] as? [String: Any], "gglib recorded no \(key)")
        if !said { frame["said"] = nil }
        return try JSONDecoder().decode(RunWait.self, from: JSONSerialization.data(withJSONObject: frame))
    }

    /// A wait whose frame carries gglib's sentence shows that sentence as it
    /// came, whatever else the frame says, a load's and a render's alike.
    func testAWaitShowsTheSentenceGglibSaid() throws {
        func line(_ wait: RunWait) -> String { ToolWork.line(for: wait, in: Self.british) }
        XCTAssertEqual(
            line(try Self.recordedWait("image_render")), "Waiting for an image render, step 3 of 20, 2 in line")
        XCTAssertEqual(line(try Self.recordedWait("model_load")), "Loading Qwen3-4B\u{2026} 1 s")
        // The sentence, not words made here from the fields beside it.
        XCTAssertEqual(
            line(RunWait(reason: .modelLoad, said: "Loading Qwen3-4B\u{2026} 1 s")), "Loading Qwen3-4B\u{2026} 1 s")
        XCTAssertEqual(
            line(RunWait(reason: .imageRender, said: "Waiting for an image render, step 3 of 20, 2 in line")),
            "Waiting for an image render, step 3 of 20, 2 in line")
        var work = ToolWork()
        work.apply(.waiting(try Self.recordedWait("image_render")))
        XCTAssertEqual(work.line(in: Self.british), "Waiting for an image render, step 3 of 20, 2 in line")
    }

    /// A frame from a gglib that sends no sentence is worded here, as it
    /// was before gglib did.
    func testAWaitWithoutASentenceIsWordedHere() throws {
        func line(_ wait: RunWait) -> String { ToolWork.line(for: wait, in: Self.british) }
        XCTAssertEqual(
            line(try Self.recordedWait("image_render", said: false)),
            "Waiting for a picture to be drawn, at step 3 of 20, place 2 in line")
        XCTAssertEqual(line(try Self.recordedWait("model_load", said: false)), "Loading Qwen3-4B\u{2026} 1 s")
    }

    /// A wait for a reason this build does not know, gglib 0.36.0's
    /// `agent_slot`, shows the sentence its frame carries, and one that
    /// came without a sentence is "Waiting…".
    func testAWaitForAReasonThisBuildDoesNotKnowShowsItsSentence() throws {
        let frame =
            #"{"reason":"agent_slot","step":0,"total":0,"position":2,"elapsed_ms":5000,"#
            + #""said":"Waiting for a free agent slot, 2 in line\#u{2026} 5 s"}"#
        var work = ToolWork()
        work.apply(.waiting(try JSONDecoder().decode(RunWait.self, from: Data(frame.utf8))))
        XCTAssertEqual(work.line(in: Self.british), "Waiting for a free agent slot, 2 in line\u{2026} 5 s")
        XCTAssertEqual(ToolWork.line(for: RunWait(reason: .other), in: Self.british), "Waiting\u{2026}")
        XCTAssertEqual(
            ToolWork.line(for: RunWait(reason: .other, position: 2, elapsedMS: 5000), in: Self.british),
            "Waiting\u{2026}")
    }

    /// The latest word of a tool is the one shown, a wait gives way to
    /// whatever comes next, and a tool's progress goes when its own call
    /// ends and not when another's does.
    func testTheLatestWordIsShownUntilItsToolEnds() {
        var work = ToolWork()
        XCTAssertTrue(work.isEmpty)
        XCTAssertNil(work.line(in: Self.british))
        XCTAssertNil(work.fraction)

        work.apply(.waiting(RunWait(reason: .modelLoad)))
        XCTAssertEqual(work.line(in: Self.british), "Loading the model\u{2026}")
        work.apply(.tool("Generate Image"))
        XCTAssertTrue(work.isEmpty, "a wait outlived the reply going on")

        work.apply(.toolProgress(progress(.loading)))
        XCTAssertNil(work.fraction, "a bar with no steps to fill it")
        work.apply(.toolProgress(progress(.sampling, pass: 1, done: 5, total: 20)))
        XCTAssertEqual(work.line(in: Self.british), "Drawing: step 5 of 20")
        XCTAssertEqual(work.fraction, 0.25)
        work.apply(.delta("words beside it"))
        XCTAssertEqual(work.line(in: Self.british), "Drawing: step 5 of 20", "text ended a tool's progress")

        work.apply(.toolEnded("another"))
        XCTAssertEqual(work.progress, progress(.sampling, pass: 1, done: 5, total: 20))
        work.apply(.toolEnded("c1"))
        XCTAssertTrue(work.isEmpty)

        work.apply(.toolProgress(progress(.sampling, done: 30, total: 20)))
        XCTAssertEqual(work.fraction, 1)
        work.end()
        XCTAssertTrue(work.isEmpty)
    }

    /// A Mac's reply holds the work its run reports, in memory, beside its
    /// tool lines, and holds none once its run has ended, here in the
    /// middle of a picture.
    func testAMacsReplyShowsTheWorkItsRunReportsUntilTheRunEnds() async throws {
        let hub = FakeChatsHub(reply: [
            [.waiting(RunWait(reason: .imageRender, step: 3, total: 20, position: 1))],
            [.tool("Generate Image")],
            [.toolProgress(progress(.sampling, pass: 1, done: 4, total: 20))],
        ])
        hub.runs.with {
            $0.holdAt = 1
            $0.ending = .failed
        }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat("a fox in snow")
        try await AppModelRunTests.until("the wait") { model.openHubReply?.cursor == 1 }
        let reply = try XCTUnwrap(model.openHubReply)
        XCTAssertEqual(reply.work.line(in: Self.british), "Waiting for a picture to be drawn, at step 3 of 20")

        hub.runs.with { $0.holdAt = 3 }
        await model.scene(.background).value
        await model.scene(.foreground).value
        try await AppModelRunTests.until("the step") { reply.cursor == 3 }
        XCTAssertEqual(reply.work.line(in: Self.british), "Drawing: step 4 of 20")
        XCTAssertEqual(reply.work.fraction, 0.2)
        XCTAssertEqual(reply.tools, ["Generate Image"])

        hub.runs.release()
        try await AppModelRunTests.until("the end") { reply.ended }
        XCTAssertTrue(reply.work.isEmpty, "a run that ended left a picture being drawn")
    }
}
