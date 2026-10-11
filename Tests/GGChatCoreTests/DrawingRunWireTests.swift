import Foundation
import XCTest

@testable import GGChatCore

/// A run that draws for a conversation kept on this device, against
/// `RunHub`: how it is put, what its report says of its frames, and which
/// decoder reads them.
final class DrawingRunWireTests: XCTestCase {
    private let image = ImageContentWireTests.pngRef

    private func request(draws: Bool) -> ChatRequest {
        ChatRequest(
            model: "Qwen3.8-27B",
            messages: [Message(role: .user, content: "a fox in snow", createdAt: Date(timeIntervalSince1970: 0))],
            returnProgress: true, draws: draws)
    }

    private func agentFrames() throws -> [String] {
        String(decoding: try Fixtures.data("gglib-agent-run-events.jsonl"), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    private func text(_ events: [RunEvent]) -> String {
        var text = ""
        for case .frame(_, let chat) in events {
            for case .delta(let piece) in chat { text += piece }
        }
        return text
    }

    /// A request that draws is put as a chat run with gglib's own tools and
    /// `draw=true`, all in the query, and its body is the body of the same
    /// request that does not: the OpenAI request and no new key. A request
    /// that does not draw has no query at all.
    func testARunThatDrawsIsPutWithItsQueryAndTheBodyUnchanged() async throws {
        let frames = try agentFrames()
        var script = RunHub.Script(frames: frames, ending: RunHub.report("run-d", "completed", lastSeq: frames.count))
        script.put = (
            201,
            #"{"id":"run-d","kind":"chat","status":"queued","created_at_ms":1,"last_seq":0,"#
                + #""frames":"agent"}"#
        )
        RunHub.serve(script, at: "draws.runs.test")
        let started = try await RunHub.provider(at: "draws.runs.test").startRun(id: "run-d", request(draws: true))
        XCTAssertEqual(
            started,
            .started(RunInfo(id: "run-d", kind: .chat, status: .queued, createdAtMs: 1, lastSeq: 0, frames: .agent)))
        let put = try XCTUnwrap(RunHub.requests(at: "draws.runs.test").first)
        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertEqual(put.url?.path(), "/v1/runs/run-d")
        XCTAssertEqual(put.url?.query(), "kind=chat&tools=builtin&draw=true")

        script.put = (201, RunHub.report("run-d", "queued", lastSeq: 0))
        RunHub.serve(script, at: "plain.runs.test")
        let plain = try await RunHub.provider(at: "plain.runs.test").startRun(id: "run-d", request(draws: false))
        guard case .started(let info) = plain else { return XCTFail("the run did not start") }
        XCTAssertNil(info.frames, "a run of chunks said how its frames are written")
        let plainPut = try XCTUnwrap(RunHub.requests(at: "plain.runs.test").first)
        XCTAssertNil(plainPut.url?.query(), "a request that does not draw gained a query")
        XCTAssertEqual(plainPut.url?.absoluteString, "http://plain.runs.test/v1/runs/run-d")
        // Keys sorted, since an encoder does not promise their order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(try ChatCompletionRequest(request(draws: false)))
        XCTAssertEqual(try encoder.encode(try ChatCompletionRequest(request(draws: true))), body)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("draw"))
    }

    /// A run's report says `frames: "agent"` when its events are an
    /// agent's, and says nothing when they are the chat route's chunks, as
    /// every gglib before said nothing: absent reads as nil, and is left
    /// out again when written.
    func testARunsReportSaysHowItsFramesAreWritten() throws {
        func info(_ extra: String) throws -> RunInfo {
            let body = #"{"id":"r","kind":"chat","status":"in_progress","created_at_ms":1,"last_seq":4\#(extra)}"#
            return try JSONDecoder().decode(RunInfo.self, from: Data(body.utf8))
        }
        XCTAssertEqual(try info(#","frames":"agent""#).frames, .agent)
        XCTAssertEqual(try info(#","frames":"openai""#).frames, .openai)
        XCTAssertNil(try info("").frames)
        XCTAssertNil(try info(#","frames":null"#).frames)
        let written = try JSONEncoder().encode(try info(""))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["created_at_ms", "id", "kind", "last_seq", "status"])
    }

    /// The decoder is the one the frames ask for: a run of agent events
    /// read as an agent's is its text, and read as the chat route's chunks
    /// is nothing; a run of chunks read as chunks is its text, as it was,
    /// and that is what a read that names no decoder does.
    func testTheFramesPickTheDecoder() async throws {
        let frames = try agentFrames()
        RunHub.serve(
            RunHub.Script(frames: frames, ending: RunHub.report("run-a", "completed", lastSeq: frames.count)),
            at: "agent.frames.test")
        let hub = RunHub.provider(at: "agent.frames.test")
        var asAgent: [RunEvent] = []
        for await event in hub.runEvents(id: "run-a", after: 0, frames: .agent) { asAgent.append(event) }
        XCTAssertEqual(text(asAgent), "Pin the version.")
        var asChunks: [RunEvent] = []
        for await event in hub.runEvents(id: "run-a", after: 0, frames: .openai) { asChunks.append(event) }
        XCTAssertEqual(text(asChunks), "")

        let recorded = String(decoding: try Fixtures.data("gglib-stream-reasoning.sse"), as: UTF8.self)
        let chunks = recorded.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { return nil }
            return String(line.dropFirst("data: ".count))
        }
        RunHub.serve(
            RunHub.Script(frames: chunks, ending: RunHub.report("run-c", "completed", lastSeq: chunks.count)),
            at: "chunk.frames.test")
        let plain = RunHub.provider(at: "chunk.frames.test")
        var named: [RunEvent] = []
        for await event in plain.runEvents(id: "run-c", after: 0, frames: .openai) { named.append(event) }
        var unnamed: [RunEvent] = []
        for await event in plain.runEvents(id: "run-c", after: 0) { unnamed.append(event) }
        XCTAssertEqual(text(named), "ok")
        XCTAssertEqual(unnamed, named, "a plain chat run read another way than it was")
    }

    /// A reply's images are ones a tool made, and are never sent back to
    /// the model: on the wire the reply is its text alone, the bare string,
    /// and its image needs no bytes in the request. The question beside it
    /// still carries its own.
    func testAReplysImagesAreNotSentBackToTheModel() throws {
        let made = ImageRef(id: "made-by-a-tool", mime: ImageRef.png, width: 1024, height: 1024)
        let request = ChatRequest(
            model: "m",
            messages: [
                Message(role: .user, content: "what is this", createdAt: .distantPast, images: [image]),
                Message(role: .assistant, content: "A fox.", createdAt: .distantPast, images: [made]),
            ],
            images: [image.id: ImageContentWireTests.png])
        let body = try JSONEncoder().encode(try ChatCompletionRequest(request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual((messages[0]["content"] as? [[String: Any]])?.count, 2, "the question lost its image")
        XCTAssertEqual(messages[1]["content"] as? String, "A fox.")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("made-by-a-tool"))
    }

    /// A word for the frames this build does not know, from a later gglib,
    /// reads as unknown and costs nothing else: the `PUT`'s answer is still
    /// a run that started, the run's last report still ends its stream as
    /// the run ended, a list holding such a run still reads the others, and
    /// events asked for that way are numbered frames that mean nothing.
    func testAnUnknownWordForTheFramesStillReads() async throws {
        let report =
            #"{"id":"run-u","kind":"chat","status":"completed","created_at_ms":1,"last_seq":2,"#
            + #""frames":"binary"}"#
        var script = RunHub.Script(frames: [#"{"x":1}"#, #"{"x":2}"#], ending: report)
        script.put = (201, report)
        RunHub.serve(script, at: "unknown.frames.test")
        let hub = RunHub.provider(at: "unknown.frames.test")
        let want = RunInfo(
            id: "run-u", kind: .chat, status: .completed, createdAtMs: 1, lastSeq: 2, frames: .unknown)
        let started = try await hub.startRun(id: "run-u", request(draws: true))
        XCTAssertEqual(started, .started(want))
        var events: [RunEvent] = []
        for await event in hub.runEvents(id: "run-u", after: 0, frames: .unknown) { events.append(event) }
        XCTAssertEqual(events, [.frame(seq: 1, events: []), .frame(seq: 2, events: []), .ended(want)])

        let plain = #"{"id":"run-p","kind":"chat","status":"queued","created_at_ms":1,"last_seq":0}"#
        let list = try JSONDecoder().decode(RunList.self, from: Data(#"{"runs":[\#(report),\#(plain)]}"#.utf8))
        XCTAssertEqual(list.runs.map(\.frames), [.unknown, nil])
        XCTAssertEqual(list.runs.map(\.id), ["run-u", "run-p"])
    }
}
