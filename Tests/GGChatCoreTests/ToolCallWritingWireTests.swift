import Foundation
import XCTest

@testable import GGChatCore

/// gglib's `tool_call_writing`: a call the model is still writing, sent
/// before its `tool_call_start`, read as a tool line marked as one being
/// written, with how many pieces of the reply's calls have streamed.
final class ToolCallWritingWireTests: XCTestCase {
    private static func writing(_ tokens: Int) -> String {
        #"{"type":"tool_call_writing","tool_name":"builtin:generate_image","display_name":"Generate Image","#
            + #""tokens":\#(tokens)}"#
    }

    /// A run that writes a call over two seconds and then makes it, as
    /// gglib's frames say it: the first count at the first named piece, a
    /// later one, then the call, and a run cut off while it wrote a second
    /// call, which ends with an error.
    private static let frames = [
        writing(1), writing(512),
        #"{"type":"tool_call_start","tool_call":{"id":"c1","name":"builtin:generate_image","arguments":"#
            + #"{"prompt":"a fox"}},"display_name":"Generate Image","args_summary":"a fox"}"#,
        writing(40),
        #"{"type":"error","message":"the model stopped at its token limit while writing a tool call"}"#,
    ]

    private static let read: [ChatEvent] = [
        .tool("Writing Generate Image\u{2026} 1 token", writing: true),
        .tool("Writing Generate Image\u{2026} 512 tokens", writing: true),
        .tool("Generate Image: a fox"),
        .toolCalled(ToolExchange(callID: "c1", name: "builtin:generate_image", arguments: #"{"prompt":"a fox"}"#)),
        .tool("Writing Generate Image\u{2026} 40 tokens", writing: true),
        .error(.stream(code: nil, message: "the model stopped at its token limit while writing a tool call")),
    ]

    private func chat(_ stream: AsyncStream<RunEvent>) async -> [ChatEvent] {
        var events: [ChatEvent] = []
        for await event in stream {
            if case .frame(_, let chat) = event { events += chat }
        }
        return events
    }

    /// Both doors read it the same: a run this phone keeps, read as an
    /// agent's, and a turn on one of the Mac's chats. Each count is a line
    /// marked as being written, the call that follows is a line of its own
    /// with the call itself, and a cut while a call is written is the run's
    /// error, as any other.
    func testACallBeingWrittenIsALineWithItsCountOnBothDoors() async throws {
        let host = "writing.runs.test"
        RunHub.serve(
            RunHub.Script(
                frames: Self.frames,
                ending: RunHub.report("run-w", "failed", lastSeq: Self.frames.count, kind: "agent")),
            at: host)
        let kept = await chat(RunHub.provider(at: host).runEvents(id: "run-w", after: 0, frames: .agent))
        XCTAssertEqual(kept, Self.read, "a run this phone keeps")
        let turn = await chat(RunHub.provider(at: host).turnEvents(runID: "run-w", after: 0))
        XCTAssertEqual(turn, Self.read, "a turn on one of the Mac's chats")
    }

    /// The count is in the locale's digits, a frame with no count is the
    /// tool's name alone, a count that does not read is no count, and a
    /// frame that names no tool means nothing here.
    func testTheCountIsInTheLocalesDigitsAndAFrameWithoutANameIsNothing() {
        func line(_ data: String, _ locale: String) -> [ChatEvent] {
            OpenAICompatibleProvider.agentEvents(SSEEvent(data: data), in: Locale(identifier: locale))
        }
        XCTAssertEqual(
            line(Self.writing(1_234_567), "en_US"),
            [.tool("Writing Generate Image\u{2026} 1,234,567 tokens", writing: true)])
        XCTAssertEqual(
            line(Self.writing(1_234_567), "de_DE"),
            [.tool("Writing Generate Image\u{2026} 1.234.567 tokens", writing: true)])
        XCTAssertEqual(
            line(#"{"type":"tool_call_writing","display_name":"Generate Image"}"#, "en_US"),
            [.tool("Writing Generate Image\u{2026}", writing: true)])
        XCTAssertEqual(
            line(#"{"type":"tool_call_writing","display_name":"Generate Image","tokens":"many"}"#, "en_US"),
            [.tool("Writing Generate Image\u{2026}", writing: true)])
        XCTAssertEqual(line(#"{"type":"tool_call_writing","tool_name":"x","tokens":3}"#, "en_US"), [])
    }
}
