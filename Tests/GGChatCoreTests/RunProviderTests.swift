import Foundation
import XCTest

@testable import GGChatCore

/// The client side of gglib's runs routes, against `RunHub`.
final class RunProviderTests: XCTestCase {
    private let request = ChatRequest(
        model: "Qwen3.8-27B",
        messages: [Message(role: .user, content: "hi", createdAt: Date(timeIntervalSince1970: 0))],
        returnProgress: true)

    /// The data lines of gglib's recorded reasoning stream, `[DONE]` aside.
    private func recordedFrames() throws -> [String] {
        let text = String(decoding: try Fixtures.data("gglib-stream-reasoning.sse"), as: UTF8.self)
        return text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { return nil }
            return String(line.dropFirst("data: ".count))
        }
    }

    private func script(_ id: String, status: String = "completed") throws -> RunHub.Script {
        let frames = try recordedFrames()
        return RunHub.Script(frames: frames, ending: RunHub.report(id, status, lastSeq: frames.count))
    }

    /// Everything one read yields.
    private func read(_ provider: some RunProvider, _ id: String, after: UInt32) async -> [RunEvent] {
        var events: [RunEvent] = []
        for await event in provider.runEvents(id: id, after: after) { events.append(event) }
        return events
    }

    /// The text and reasoning a list of events adds up to.
    private func reply(of events: [RunEvent]) -> (text: String, reasoning: String) {
        var text = ""
        var reasoning = ""
        for case .frame(_, let chat) in events {
            for event in chat {
                if case .delta(let piece) = event { text += piece }
                if case .reasoning(let piece) = event { reasoning += piece }
            }
        }
        return (text, reasoning)
    }

    /// A 201 starts the run with the body the chat route is sent, at the id
    /// this device minted. A 404 or 405 carrying no run code is a hub with no
    /// runs; a run code, or any other refusal, is a failure.
    func testAPutStartsARunAndAHubWithoutTheRouteIsUnsupported() async throws {
        let id = "0B7C5E1A-9D2F-4C33-8E11-2A6F0D4B9C71"
        var started = try script(id)
        started.put = (201, RunHub.report(id, "queued", lastSeq: 0))
        RunHub.serve(started, at: "put.runs.test")
        let result = try await RunHub.provider(at: "put.runs.test").startRun(id: id, request)
        XCTAssertEqual(
            result, .started(RunInfo(id: id, kind: .chat, status: .queued, createdAtMs: 1_790_000_000_000, lastSeq: 0)))
        let put = try XCTUnwrap(RunHub.requests(at: "put.runs.test").first)
        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertEqual(put.url?.path(), "/v1/runs/\(id)")
        XCTAssertEqual(put.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        // Compared as JSON: the encoder's key order is not fixed.
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(put.httpBody ?? put.bodyStreamData))
        let chat = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        XCTAssertEqual(sent as? NSDictionary, chat as? NSDictionary, "the run was not sent the chat request")

        let older = [(404, ""), (405, ""), (404, #"{"error":{"code":"model_not_found","message":"no"}}"#)]
        for (index, (status, body)) in older.enumerated() {
            var answer = try script(id)
            answer.put = (status, body)
            RunHub.serve(answer, at: "older-\(index).runs.test")
            let result = try await RunHub.provider(at: "older-\(index).runs.test").startRun(id: id, request)
            XCTAssertEqual(result, .unsupported, "\(status) \(body) was not read as a hub without runs")
        }
        let refusals = [(429, RunCode.tooManyRuns), (404, RunCode.notFound), (409, RunCode.conflict), (400, "x")]
        for (index, (status, code)) in refusals.enumerated() {
            var answer = try script(id)
            answer.put = (status, #"{"error":{"code":"\#(code)","message":"refused"}}"#)
            RunHub.serve(answer, at: "refused-\(index).runs.test")
            do {
                let result = try await RunHub.provider(at: "refused-\(index).runs.test").startRun(id: id, request)
                XCTFail("\(status) \(code) started as \(result)")
            } catch {
                XCTAssertEqual(error, .server(status: status, code: code, message: "refused"))
            }
        }
    }

    /// Each numbered event is one frame carrying what the chat route would
    /// have read from it, and the stream ends with the run's report.
    func testEventsAreFramesNumberedFromOneThenTheRunsReport() async throws {
        RunHub.serve(try script("run-a"), at: "events.runs.test")
        let events = await read(RunHub.provider(at: "events.runs.test"), "run-a", after: 0)
        let frames = try recordedFrames()
        XCTAssertEqual(events.count, frames.count + 1)
        let seqs = events.compactMap { event -> UInt32? in
            if case .frame(let seq, _) = event { return seq }
            return nil
        }
        XCTAssertEqual(seqs, Array(1...UInt32(frames.count)))
        XCTAssertEqual(
            events.last,
            .ended(
                RunInfo(
                    id: "run-a", kind: .chat, status: .completed, createdAtMs: 1_790_000_000_000,
                    lastSeq: UInt32(frames.count))))
        XCTAssertEqual(reply(of: events).text, "ok")
        XCTAssertFalse(reply(of: events).reasoning.isEmpty, "the reasoning was not read")
        let asked = try XCTUnwrap(RunHub.requests(at: "events.runs.test").first?.url)
        XCTAssertEqual(asked.path(), "/v1/runs/run-a/events")
        XCTAssertEqual(asked.query(), "after=0")
    }

    /// A run has no `.finished`, so its usage frame is passed on as what the
    /// call counted, once, in the frame that carried it, with the finish
    /// reason read in the frame before. A read that starts after that frame
    /// has the counts and no reason. The chat route says both in `.finished`
    /// and passes on no `.usage`. The frames are the recorded stream's, with
    /// gglib's two context keys added to its usage frame by hand, pending
    /// gglib's own recording.
    func testARunsUsageFrameIsPassedOnWithItsFinishReason() async throws {
        var frames = try recordedFrames()
        let last = UInt32(frames.count)
        let extended = frames[frames.count - 1].replacingOccurrences(
            of: #""total_tokens":85}"#, with: #""total_tokens":85,"context_size":8192,"trimmed_messages":2}"#)
        XCTAssertNotEqual(extended, frames[frames.count - 1], "the recorded usage frame is not where it was")
        frames[frames.count - 1] = extended
        let want = Usage(
            promptTokens: 57, completionTokens: 28, totalTokens: 85, cachedTokens: 42, contextSize: 8_192,
            trimmedMessages: 2)
        func counted(_ events: [RunEvent]) -> [RunEvent] {
            events.filter { event in
                guard case .frame(_, let chat) = event else { return false }
                return chat.contains { if case .usage = $0 { true } else { false } }
            }
        }
        let script = RunHub.Script(frames: frames, ending: RunHub.report("run-u", "completed", lastSeq: frames.count))
        RunHub.serve(script, at: "usage.runs.test")
        let provider = RunHub.provider(at: "usage.runs.test")
        let whole = await read(provider, "run-u", after: 0)
        XCTAssertEqual(counted(whole), [.frame(seq: last, events: [.usage(want, reason: "stop")])])
        let late = await read(provider, "run-u", after: last - 1)
        XCTAssertEqual(counted(late), [.frame(seq: last, events: [.usage(want, reason: nil)])])

        let body = Data((frames.map { "data: \($0)\n\n" }.joined() + "data: [DONE]\n\n").utf8)
        StubURLProtocol.register(
            host: "usage.chat.test", path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [body]))
        let chat = OpenAICompatibleProvider(
            baseURL: try XCTUnwrap(URL(string: "http://usage.chat.test/v1")), session: StubURLProtocol.makeSession())
        var streamed: [ChatEvent] = []
        for await event in chat.stream(request) { streamed.append(event) }
        XCTAssertEqual(streamed.last, .finished(reason: "stop", usage: want))
        XCTAssertFalse(streamed.contains { if case .usage = $0 { true } else { false } }, "the chat route sent .usage")
    }

    /// The stream dropped after every byte of it in turn, then read again
    /// from the last frame it yielded, adds up to the same reply as one
    /// unbroken read: no event applied twice, none skipped, and none taken
    /// from half an event.
    func testAStreamCutAtEveryByteReadsOnFromItsCursorToTheSameReply() async throws {
        let whole = try script("run-cut")
        let length = RunHub.eventsBody(whole, after: 0).count
        RunHub.serve(whole, at: "whole.runs.test")
        let unbroken = reply(of: await read(RunHub.provider(at: "whole.runs.test"), "run-cut", after: 0))
        for cut in 0..<length {
            let host = "cut-\(cut).runs.test"
            RunHub.serve(whole, at: host)
            RunHub.cut(at: cut, at: host)
            let provider = RunHub.provider(at: host)
            let first = await read(provider, "run-cut", after: 0)
            guard case .dropped = first.last else { return XCTFail("a cut at \(cut) did not read as a drop") }
            var cursor: UInt32 = 0
            for case .frame(let seq, _) in first { cursor = seq }
            let rest = await read(provider, "run-cut", after: cursor)
            let joined = reply(of: first + rest)
            XCTAssertEqual(joined.text, unbroken.text, "a cut at byte \(cut) of \(length)")
            XCTAssertEqual(joined.reasoning, unbroken.reasoning, "a cut at byte \(cut) of \(length)")
        }
    }

    /// A hub that sends from further back than it was asked has none of it
    /// applied a second time.
    func testAnEventAtOrBelowTheCursorIsNotAppliedAgain() async throws {
        var repeating = try script("run-again")
        repeating.ignoresAfter = true
        RunHub.serve(repeating, at: "again.runs.test")
        let events = await read(RunHub.provider(at: "again.runs.test"), "run-again", after: 20)
        guard case .frame(let first, _)? = events.first else { return XCTFail("no frame was read") }
        XCTAssertEqual(first, 21)
    }

    /// `not_found` is a run the hub no longer has. Any other 4xx is a refusal
    /// that asking again would repeat. A 5xx, a 2xx that is not an event
    /// stream (a captive portal's page, say), no answer, or an end with no
    /// report is a drop to read again from.
    func testNotFoundARefusalAndADropAreToldApart() async throws {
        let codes = [404: "not_found", 401: "invalid_api_key", 403: "not_yours", 502: "tunnel_unavailable"]
        func refusal(_ status: Int) -> ProviderError {
            .server(status: status, code: codes[status], message: "refused")
        }
        let answers: [(status: Int, want: RunEvent)] = [
            (404, .notFound), (401, .refused(refusal(401))), (403, .refused(refusal(403))),
            (200, .dropped(.invalidResponse("the answer was text/html, not an event stream"))),
            (502, .dropped(refusal(502))),
        ]
        for (index, answer) in answers.enumerated() {
            var script = try script("run-\(index)")
            if let code = codes[answer.status] {
                script.refusal = (answer.status, #"{"error":{"code":"\#(code)","message":"refused"}}"#)
            } else {
                script.eventsType = "text/html"
            }
            RunHub.serve(script, at: "told-\(index).runs.test")
            let read = await read(RunHub.provider(at: "told-\(index).runs.test"), "run-\(index)", after: 0)
            XCTAssertEqual(read.last, answer.want, "an answer of \(answer.status)")
        }
        let unreachable = await read(RunHub.provider(at: "nobody.runs.test"), "run-x", after: 0)
        guard case .dropped(.transport?)? = unreachable.last else { return XCTFail("\(unreachable)") }
    }

    /// A last report the hub sent but this build cannot read is a refusal,
    /// not a drop: reading again would get the same report.
    func testAReportThatCannotBeReadIsARefusal() async throws {
        var unreadable = try script("run-odd")
        unreadable.ending = #"{"id":"run-odd","status":42}"#
        RunHub.serve(unreadable, at: "odd.runs.test")
        let events = await read(RunHub.provider(at: "odd.runs.test"), "run-odd", after: 0)
        guard case .refused(.decoding)? = events.last else { return XCTFail("\(String(describing: events.last))") }
        XCTAssertEqual(events.dropLast().count, try recordedFrames().count, "the frames before it were not read")
    }

    /// Cancel posts to the run's own route and reads its report.
    func testCancelPostsToTheRunAndReadsItsReport() async throws {
        var cancelled = try script("run-stop", status: "cancelled")
        cancelled.ending = RunHub.report("run-stop", "cancelled", lastSeq: 4)
        RunHub.serve(cancelled, at: "cancel.runs.test")
        let info = try await RunHub.provider(at: "cancel.runs.test").cancelRun(id: "run-stop")
        XCTAssertEqual(info.status, .cancelled)
        let post = try XCTUnwrap(RunHub.requests(at: "cancel.runs.test").first)
        XCTAssertEqual(post.httpMethod, "POST")
        XCTAssertEqual(post.url?.path(), "/v1/runs/run-stop/cancel")
    }

    /// A run's id reaches the hub on every route and no log line.
    func testARunsIDNeverReachesALogLine() async throws {
        let id = "run-must-not-be-logged-5c1e"
        let log = CapturingLogSink()
        var answer = try script(id)
        answer.put = (201, RunHub.report(id, "queued", lastSeq: 0))
        RunHub.serve(answer, at: "quiet.runs.test")
        let provider = RunHub.provider(at: "quiet.runs.test", log: log)
        _ = try await provider.startRun(id: id, request)
        _ = await read(provider, id, after: 0)
        _ = try await provider.cancelRun(id: id)
        _ = await read(RunHub.provider(at: "nobody.runs.test", log: log), id, after: 0)
        XCTAssertEqual(RunHub.requests(at: "quiet.runs.test").count, 3)
        XCTAssertGreaterThan(log.lines.count, 3, "the provider does log, so an empty log would prove nothing")
        for line in log.lines {
            XCTAssertFalse(line.contains(id), "a run's id in a log line: \(line)")
        }
        XCTAssertEqual(
            Redaction.describe(try XCTUnwrap(URL(string: "http://h:1/v1/runs/\(id)/events?after=3"))),
            "http://h:1/v1/runs/<run>/events")
    }
}

extension URLRequest {
    /// A body that reaches a protocol as a stream, read whole.
    var bodyStreamData: Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
            data.append(buffer, count: count)
        }
        return data
    }
}
