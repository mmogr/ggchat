import XCTest

@testable import GGChatCore

/// gglib's `preview` event, the latest look at a picture being drawn, as a
/// run's reader meets it: `event: preview` with no `id:` line, between the
/// numbered frames (`gglib-proxy/src/runs/sse.rs`).
final class PreviewWireTests: XCTestCase {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])

    private static func preview(step: Int, id: String? = nil, b64: String? = nil) -> String {
        let data =
            #"{"tool_call_id":"c3","frame":{"mime":"image/png","step":\#(step),"total":20,"#
            + #""b64":"\#(b64 ?? png.base64EncodedString())"}}"#
        return "event: preview\n" + (id.map { "id: \($0)\n" } ?? "") + "data: \(data)\n\n"
    }

    private func frames() throws -> [String] {
        String(decoding: try Fixtures.data("gglib-agent-run-events.jsonl"), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    private func script(_ id: String, beside: [Int: String]) throws -> RunHub.Script {
        let frames = try frames()
        var script = RunHub.Script(
            frames: frames, ending: RunHub.report(id, "completed", lastSeq: frames.count, kind: "agent"))
        script.beside = beside
        return script
    }

    private func read(_ stream: AsyncStream<RunEvent>) async -> [RunEvent] {
        var events: [RunEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func seqs(_ events: [RunEvent]) -> [UInt32] {
        events.compactMap { if case .frame(let seq, _) = $0 { seq } else { nil } }
    }

    private func looks(_ events: [RunEvent]) -> [PreviewFrame] {
        events.compactMap { if case .preview(let frame) = $0 { frame } else { nil } }
    }

    /// A preview is passed on where it came, with its call, its step and its
    /// bytes, and every numbered frame around it is still passed on once:
    /// it is read ahead of the numbering, so one that came with no id (and
    /// so with the id of the frame before it, as an event stream has it) is
    /// not dropped as a frame already read, and one that came with an id of
    /// its own, which gglib never sends, moves no cursor past the frames
    /// that follow.
    func testAPreviewIsReadAheadOfTheNumberingAndMovesNoCursor() async throws {
        let host = "preview.runs.test"
        let count = try frames().count
        RunHub.serve(
            try script("run-p", beside: [8: Self.preview(step: 3), 9: Self.preview(step: 4, id: "99")]), at: host)
        let events = await read(RunHub.provider(at: host).turnEvents(runID: "run-p", after: 0))
        XCTAssertEqual(seqs(events), Array(1...UInt32(count)), "a preview moved the cursor")
        XCTAssertEqual(
            looks(events),
            [
                PreviewFrame(callID: "c3", step: 3, total: 20, data: Self.png),
                PreviewFrame(callID: "c3", step: 4, total: 20, data: Self.png),
            ])
        let order = events.map { event -> String in
            switch event {
            case .frame(let seq, _): "\(seq)"
            case .preview(let frame): "look \(frame.step)"
            default: "end"
            }
        }
        XCTAssertEqual(order[7...10], ["8", "look 3", "9", "look 4"])
        XCTAssertEqual(order.last, "end")

        // Read on from the frame before it, as a reader that comes back is.
        let later = await read(RunHub.provider(at: host).turnEvents(runID: "run-p", after: 8))
        XCTAssertEqual(seqs(later), Array(9...UInt32(count)))
        XCTAssertEqual(looks(later).map(\.step), [4])
    }

    /// A run read as the chat route's frames passes a preview on the same
    /// way, and one that does not read, its bytes not base64 or its frame
    /// missing, is passed over with the frames around it untouched.
    func testAPreviewThatDoesNotReadIsPassedOver() async throws {
        let host = "preview-bad.runs.test"
        let count = try frames().count
        let beside = [
            2: Self.preview(step: 1, b64: "not base64!"),
            3: "event: preview\ndata: {\"tool_call_id\":\"c3\"}\n\n",
            4: Self.preview(step: 2),
        ]
        RunHub.serve(try script("run-b", beside: beside), at: host)
        let events = await read(RunHub.provider(at: host).runEvents(id: "run-b", after: 0))
        XCTAssertEqual(seqs(events), Array(1...UInt32(count)))
        XCTAssertEqual(looks(events), [PreviewFrame(callID: "c3", step: 2, total: 20, data: Self.png)])
    }
}
