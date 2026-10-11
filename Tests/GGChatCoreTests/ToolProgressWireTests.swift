import XCTest

@testable import GGChatCore

/// The frames a picture being drawn sends, as gglib records them in
/// `contracts/runs/tool_progress.json` (copied here byte for byte as
/// `gglib-tool-progress.json` from gglib's `feat(agent): a tool's own
/// deadline, and its progress on every door`, which is not merged yet), read
/// by the agent decoder a hub's run is read with.
final class ToolProgressWireTests: XCTestCase {
    private static let call = "call_1"

    private func events(_ line: String) -> [ChatEvent] {
        OpenAICompatibleProvider.agentEvents(SSEEvent(data: line))
    }

    /// The recorded frames, each as the events it means.
    private func recorded() throws -> [[ChatEvent]] {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-tool-progress.json"))
        return try XCTUnwrap(object as? [Any]).map { frame in
            events(String(decoding: try JSONSerialization.data(withJSONObject: frame), as: UTF8.self))
        }
    }

    /// A reply that waits behind another picture, then draws one: the wait
    /// with its step and place, the tool's line, each stage of the picture
    /// with the counts it reported and no others, and the call's end ahead
    /// of the image it made.
    func testTheRecordedFramesOfAPictureReadAsItsWaitItsStagesAndItsEnd() throws {
        func stage(
            _ stage: ToolProgress.Stage, pass: Int? = nil, done: Int? = nil, total: Int? = nil, position: Int? = nil
        ) -> [ChatEvent] {
            [
                .toolProgress(
                    ToolProgress(
                        callID: Self.call, stage: stage, pass: pass, done: done, total: total, position: position))
            ]
        }
        let image = ImageRef(
            id: "8b6df8c11847ada8266bad5b8737f94c208c411a3ebe18e27aad31bfb7eb8767", mime: "image/png", width: 1024,
            height: 1024)
        XCTAssertEqual(
            try recorded(),
            [
                [.waiting(RunWait(reason: .imageRender, step: 12, total: 20, position: 1))],
                [.tool("Generate Image")],
                stage(.queued, position: 1),
                stage(.loading),
                stage(.sampling, pass: 1, done: 1, total: 20),
                stage(.sampling, pass: 1, done: 20, total: 20),
                stage(.decoding),
                stage(.finishing),
                [.toolEnded(Self.call), .images([image])],
            ])
    }

    /// A wait for a model to load is its own reason. A stage or a reason
    /// this build does not know, and a frame missing what it must have,
    /// mean nothing: the reply reads on.
    func testAWaitForAModelAndFramesThatDoNotReadMeanNothing() {
        XCTAssertEqual(
            events(#"{"type":"waiting","reason":"model_load","step":0,"total":0,"position":0}"#),
            [.waiting(RunWait(reason: .modelLoad))])
        XCTAssertEqual(events(#"{"type":"waiting","reason":"disk","step":0,"total":0,"position":0}"#), [])
        XCTAssertEqual(events(#"{"type":"waiting","reason":"model_load"}"#), [])
        XCTAssertEqual(events(#"{"type":"tool_progress","tool_call_id":"c1","stage":"upscaling"}"#), [])
        XCTAssertEqual(events(#"{"type":"tool_progress","stage":"loading"}"#), [])
        XCTAssertEqual(
            events(#"{"type":"tool_call_complete","tool_name":"t","result":{"content":"x","success":true}}"#), [])
    }
}
