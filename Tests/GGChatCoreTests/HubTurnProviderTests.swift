import Foundation
import XCTest

@testable import GGChatCore

/// A turn on one of the hub's chats, against `RunHub`: where it is put and
/// with what body, what each refusal means, and how the agent run's events
/// are read. The events are `gglib-agent-run-events.jsonl`, one
/// `AgentEvent` per line as gglib serialises it
/// (`gglib-core/src/domain/agent/events.rs` at gglib a6f36850, the shapes
/// its `events_tests.rs` pins), framed as `runs/sse.rs` frames them.
///
/// The fixture's `turn_usage` line follows gglib pull request #1273, whose
/// recorded frame is in `contracts/runs/turn_made.json`: every key the line
/// has is a key of that frame with the same type (`prompt_tokens`,
/// `completion_tokens`, `duration_ms`, `finish_reason`, `context_size`), and
/// the line keeps fewer keys than the frame.
final class HubTurnProviderTests: XCTestCase {
    private let turn = HubTurn(conversationID: 12, content: "And how do I fix it?")
    private let id = "5B1E0C2A-7D11-4F0E-9C3B-2E8A1D6F4B90"

    private func frames() throws -> [String] {
        String(decoding: try Fixtures.data("gglib-agent-run-events.jsonl"), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    private func script(put: (Int, String)) throws -> RunHub.Script {
        let frames = try frames()
        var script = RunHub.Script(
            frames: frames, ending: RunHub.report(id, "completed", lastSeq: frames.count, kind: "agent"))
        script.put = put
        return script
    }

    private typealias Started = Result<RunStart, HubTurnFailure>

    private func start(_ put: (Int, String), at host: String, turn: HubTurn? = nil) async throws -> Started {
        RunHub.serve(try script(put: put), at: host)
        do throws(HubTurnFailure) {
            return .success(try await RunHub.provider(at: host).startTurn(runID: id, turn: turn ?? self.turn))
        } catch {
            return .failure(error)
        }
    }

    private func refusal(_ status: Int, _ code: String) -> (Int, String) {
        (status, #"{"error":{"message":"refused","type":"invalid_request_error","code":"\#(code)"}}"#)
    }

    /// The turn is put under the id this device minted, as an agent run, with
    /// the key, and its body is the turn's two keys and nothing else.
    func testATurnIsPutAsAnAgentRunWithOnlyItsTwoKeys() async throws {
        let host = "turn-put.test"
        let started = try await start((201, RunHub.report(id, "queued", lastSeq: 0, kind: "agent")), at: host)
        XCTAssertEqual(
            try started.get(),
            .started(RunInfo(id: id, kind: .agent, status: .queued, createdAtMs: 1_790_000_000_000, lastSeq: 0)))
        let put = try XCTUnwrap(RunHub.requests(at: host).first)
        XCTAssertEqual(put.httpMethod, "PUT")
        XCTAssertEqual(put.url?.path(), "/v1/runs/\(id)")
        XCTAssertEqual(put.url?.query(), "kind=agent")
        XCTAssertEqual(put.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        let body = try XCTUnwrap(put.httpBody ?? put.bodyStreamData)
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent.keys.sorted(), ["content", "conversation_id"])
        XCTAssertEqual(sent["conversation_id"] as? Int, 12)
        XCTAssertEqual(sent["content"] as? String, "And how do I fix it?")

        let again = try await start((200, RunHub.report(id, "in_progress", lastSeq: 4, kind: "agent")), at: host)
        guard case .started(let info) = try again.get() else { return XCTFail("a repeated id did not start") }
        XCTAssertEqual(info.status, .inProgress)
    }

    /// A turn that says the Thinking choice is put with it, as the word.
    func testATurnThatSaysTheThinkingChoiceIsPutWithIt() async throws {
        let host = "turn-thinking.test"
        let said = HubTurn(conversationID: 12, content: "Answer in one line.", thinking: .off)
        _ = try await start((201, RunHub.report(id, "queued", lastSeq: 0, kind: "agent")), at: host, turn: said)
        let put = try XCTUnwrap(RunHub.requests(at: host).first)
        let body = try XCTUnwrap(put.httpBody ?? put.bodyStreamData)
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent.keys.sorted(), ["content", "conversation_id", "thinking"])
        XCTAssertEqual(sent["thinking"] as? String, "off")
    }

    /// A chat with no model and a chat with a reply already being written
    /// each have a refusal of their own, told apart from the rest.
    func testNoModelAndAReplyInProgressAreTheirOwnRefusals() async throws {
        let noModel = try await start(refusal(422, "no_model"), at: "turn-no-model.test")
        XCTAssertEqual(noModel, .failure(.noModel))
        let busy = try await start(refusal(409, "conflict"), at: "turn-busy.test")
        XCTAssertEqual(busy, .failure(.replyInProgress))
        let gone = try await start(refusal(404, "conversation_not_found"), at: "turn-gone.test")
        XCTAssertEqual(gone, .failure(.chatGone))
    }

    /// Every other answer the hub gives a turn is a refusal carrying its
    /// sentence, a hub with no runs route is one without runs, and no answer
    /// at all is a turn that may have started.
    func testEveryOtherAnswerMeansWhatItShould() async throws {
        let refused = [
            (400, "invalid_request"), (403, "device_not_named"), (429, "agent_busy"), (503, "runs_unavailable"),
            (503, "shutting_down"), (422, "something_else"), (409, "not_yours"),
        ]
        for (index, (status, code)) in refused.enumerated() {
            let result = try await start(refusal(status, code), at: "turn-refused-\(index).test")
            XCTAssertEqual(
                result, .failure(.refused(.server(status: status, code: code, message: "refused"))), "\(status) \(code)"
            )
        }
        for (index, answer) in [(404, ""), (405, "")].enumerated() {
            let result = try await start(answer, at: "turn-older-\(index).test")
            XCTAssertEqual(result, .success(.unsupported), "\(answer)")
        }
        let odd = try await start((201, "{}"), at: "turn-odd.test")
        guard case .failure(.refused(.decoding)) = odd else { return XCTFail("an unreadable run started: \(odd)") }

        let nobody: HubTurnFailure?
        do {
            _ = try await RunHub.provider(at: "turn-nobody.test").startTurn(runID: id, turn: turn)
            nobody = nil
        } catch {
            nobody = error
        }
        guard case .lost(.transport)? = nobody else {
            return XCTFail("no answer was not a lost turn: \(nobody as Any)")
        }
    }

    /// The run's events are read as an agent's: text, reasoning, a line per
    /// tool call and what a finished model call counted, every event a frame
    /// whether or not it means anything here, then the run's report.
    func testAnAgentRunsEventsAreItsTextReasoningAndToolLines() async throws {
        let host = "turn-events.test"
        RunHub.serve(try script(put: (201, "")), at: host)
        var events: [RunEvent] = []
        for await event in RunHub.provider(at: host).turnEvents(runID: id, after: 0) { events.append(event) }
        let count = try frames().count
        let seqs = events.compactMap { if case .frame(let seq, _) = $0 { seq } else { nil } }
        XCTAssertEqual(seqs, Array(1...UInt32(count)))
        let chat = events.flatMap { event -> [ChatEvent] in
            if case .frame(_, let chat) = event { return chat }
            return []
        }
        XCTAssertEqual(
            chat,
            [
                .reasoning("The lock file"), .reasoning(" moved."), .tool("Read File: Cargo.lock"), .tool("List Dir"),
                .delta("Pin "), .delta("the version."),
                .usage(Usage(promptTokens: 812, completionTokens: 12, contextSize: 8_192), reason: "stop"),
            ])
        XCTAssertEqual(
            events.last,
            .ended(
                RunInfo(
                    id: id, kind: .agent, status: .completed, createdAtMs: 1_790_000_000_000, lastSeq: UInt32(count))))
        let asked = try XCTUnwrap(RunHub.requests(at: host).first?.url)
        XCTAssertEqual(asked.path(), "/v1/runs/\(id)/events")
        XCTAssertEqual(asked.query(), "after=0")
    }

    /// A turn naming an image the hub does not hold is refused as such, and
    /// started no run. A turn with images refused as `invalid_request` is a
    /// gglib from before images; a turn of text alone refused the same way
    /// stays a refusal.
    func testAnImageTheHubDoesNotHoldAndAGglibWithoutImagesAreTheirOwnRefusals() async throws {
        let pictured = HubTurn(conversationID: 12, content: "", images: ["8d5c"])
        let gone = try await start(refusal(400, "attachment_not_found"), at: "turn-image-gone.test", turn: pictured)
        XCTAssertEqual(gone, .failure(.imageGone))
        let older = try await start(refusal(400, "invalid_request"), at: "turn-image-older.test", turn: pictured)
        XCTAssertEqual(older, .failure(.takesNoImages))
        let text = try await start(refusal(400, "invalid_request"), at: "turn-text-invalid.test")
        XCTAssertEqual(text, .failure(.refused(.server(status: 400, code: "invalid_request", message: "refused"))))
        let blind = try await start(refusal(400, "model_cannot_read_images"), at: "turn-blind.test", turn: pictured)
        XCTAssertEqual(
            blind, .failure(.refused(.server(status: 400, code: "model_cannot_read_images", message: "refused"))))
    }

    /// An error the run reports is passed on, and an event this build
    /// cannot read is passed over.
    func testAnErrorIsPassedOnAndAnEventThatCannotBeReadIsPassedOver() {
        XCTAssertEqual(
            OpenAICompatibleProvider.agentEvents(SSEEvent(data: #"{"type":"error","message":"it broke"}"#)),
            [.error(.stream(code: nil, message: "it broke"))])
        XCTAssertEqual(OpenAICompatibleProvider.agentEvents(SSEEvent(data: "not json")), [])
        XCTAssertEqual(OpenAICompatibleProvider.agentEvents(SSEEvent(data: #"{"type":"text_delta"}"#)), [])
        XCTAssertEqual(OpenAICompatibleProvider.agentEvents(SSEEvent(data: "")), [])
    }

    /// `turn_usage` is what one finished model call counted, flat: the
    /// counts, the context's size and what was trimmed under the names a
    /// chat stream's `usage` gives them, and why the call ended. Every one is
    /// optional and absent is unknown, as from a gglib that sends only the
    /// completion count. Counts that cannot be read pass the event over.
    func testATurnUsageEventIsThatCallsCounts() {
        func counted(_ fields: String) -> [ChatEvent] {
            OpenAICompatibleProvider.agentEvents(SSEEvent(data: #"{"type":"turn_usage","duration_ms":900\#(fields)}"#))
        }
        XCTAssertEqual(
            counted(
                #","model":"qwen3-8b","prompt_tokens":31000,"cached_tokens":9,"completion_tokens":400,"#
                    + #""finish_reason":"length","context_size":32768,"trimmed_messages":3"#),
            [
                .usage(
                    Usage(promptTokens: 31_000, completionTokens: 400, contextSize: 32_768, trimmedMessages: 3),
                    reason: "length")
            ])
        XCTAssertEqual(
            counted(#","completion_tokens":12"#), [.usage(Usage(completionTokens: 12), reason: nil)])
        XCTAssertEqual(counted(""), [.usage(Usage(), reason: nil)])
        XCTAssertEqual(
            counted(#","prompt_tokens":7,"completion_tokens":1,"finish_reason":"tool_calls""#),
            [.usage(Usage(promptTokens: 7, completionTokens: 1), reason: "tool_calls")])
        XCTAssertEqual(
            counted(#","prompt_tokens":7,"completion_tokens":1,"context_size":"big","trimmed_messages":[2]"#),
            [.usage(Usage(promptTokens: 7, completionTokens: 1), reason: nil)], "a bad size cost the counts")
        XCTAssertEqual(counted(#","prompt_tokens":"many""#), [])
        XCTAssertEqual(counted(#","finish_reason":7"#), [])
    }

    /// Stop is the run's cancel.
    func testCancellingATurnCancelsItsRun() async throws {
        let host = "turn-cancel.test"
        RunHub.serve(try script(put: (201, "")), at: host)
        let info = try await RunHub.provider(at: host).cancelTurn(runID: id)
        XCTAssertEqual(info.kind, .agent)
        let cancel = try XCTUnwrap(RunHub.requests(at: host).first)
        XCTAssertEqual(cancel.httpMethod, "POST")
        XCTAssertEqual(cancel.url?.path(), "/v1/runs/\(id)/cancel")
    }
}
