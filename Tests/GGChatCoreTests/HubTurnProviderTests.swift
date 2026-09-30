import Foundation
import XCTest

@testable import GGChatCore

/// A turn on one of the hub's chats, against `RunHub`: where it is put and
/// with what body, what each refusal means, and how the agent run's events
/// are read. The events are `gglib-agent-run-events.jsonl`, one
/// `AgentEvent` per line as gglib serialises it
/// (`gglib-core/src/domain/agent/events.rs` at gglib a6f36850, the shapes
/// its `events_tests.rs` pins), framed as `runs/sse.rs` frames them.
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

    private func start(_ put: (Int, String), at host: String) async throws -> Result<RunStart, HubTurnFailure> {
        RunHub.serve(try script(put: put), at: host)
        do throws(HubTurnFailure) {
            return .success(try await RunHub.provider(at: host).startTurn(runID: id, turn: turn))
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

    /// The run's events are read as an agent's: text, reasoning and a line
    /// per tool call, every event a frame whether or not it means anything
    /// here, then the run's report.
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
