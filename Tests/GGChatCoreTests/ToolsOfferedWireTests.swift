import Foundation
import XCTest

@testable import GGChatCore

/// A paired Mac that offers its MCP servers' tools: what its answer about
/// drawing says of them, and how a run that carries them is put.
final class ToolsOfferedWireTests: XCTestCase {
    /// One row of the query table: the request's flags, the host it is put
    /// to, and the query it is put with.
    private struct Row {
        var host: String
        var runsTools: Bool
        var draws: Bool
        var chosen: UInt64?
        var query: String?
    }

    /// An answer that names servers offers their tools whether or not the
    /// Mac can draw; one that names none, says `null`, or has no such key,
    /// as a gglib from before the list, offers none.
    func testAnAnswerThatNamesServersOffersToolsWhetherOrNotItCanDraw() throws {
        func drawing(_ body: String) throws -> Drawing {
            try JSONDecoder().decode(Drawing.self, from: Data(body.utf8))
        }
        let cannot =
            #"{"available":false,"code":"drawing_unavailable","reason":"there is no image model","#
            + #""mcp_servers":["tavily"]}"#
        let refused = try drawing(cannot)
        XCTAssertFalse(refused.available)
        XCTAssertEqual(refused.mcpServers, ["tavily"])
        XCTAssertTrue(refused.offersTools, "a Mac that cannot draw did not offer its servers")
        XCTAssertTrue(try drawing(#"{"available":true,"model":"flux-dev","mcp_servers":["tavily","fs"]}"#).offersTools)

        for none in [
            #"{"available":true,"model":"flux-dev"}"#, #"{"available":true,"model":"flux-dev","mcp_servers":null}"#,
            #"{"available":true,"model":"flux-dev","mcp_servers":[]}"#,
        ] {
            XCTAssertFalse(try drawing(none).offersTools, none)
        }
        XCTAssertNil(try drawing(#"{"available":false}"#).mcpServers)
    }

    /// A run with tools is put as a chat run with gglib's tools, and adds
    /// `draw=true` only when it draws, with the chosen image model only
    /// then; a run with neither has no query. The body is the same in every
    /// one, and says nothing of tools.
    func testARunWithToolsIsPutWithThemAndDrawsOnlyWhenItDraws() async throws {
        func request(runsTools: Bool, draws: Bool, chosen: UInt64?) -> ChatRequest {
            ChatRequest(
                model: "Qwen3.8-27B",
                messages: [Message(role: .user, content: "what is new?", createdAt: Date(timeIntervalSince1970: 0))],
                returnProgress: true, draws: draws, imageModelID: chosen, runsTools: runsTools)
        }
        let table = [
            Row(host: "tools.offered.test", runsTools: true, draws: false, query: "kind=chat&tools=builtin"),
            Row(
                host: "tools.draws.offered.test", runsTools: true, draws: true,
                query: "kind=chat&tools=builtin&draw=true"),
            Row(
                host: "tools.chosen.offered.test", runsTools: true, draws: true, chosen: 7,
                query: "kind=chat&tools=builtin&draw=true&image_model=7"),
            Row(
                host: "tools.unchosen.offered.test", runsTools: true, draws: false, chosen: 7,
                query: "kind=chat&tools=builtin"),
            Row(host: "plain.offered.test", runsTools: false, draws: false),
        ]
        var script = RunHub.Script(frames: [], ending: RunHub.report("run-t", "completed", lastSeq: 0))
        script.put = (201, RunHub.report("run-t", "queued", lastSeq: 0))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let plainBody = try encoder.encode(
            try ChatCompletionRequest(request(runsTools: false, draws: false, chosen: nil)))
        for row in table {
            RunHub.serve(script, at: row.host)
            let sent = request(runsTools: row.runsTools, draws: row.draws, chosen: row.chosen)
            _ = try await RunHub.provider(at: row.host).startRun(id: "run-t", sent)
            let put = try XCTUnwrap(RunHub.requests(at: row.host).first)
            XCTAssertEqual(put.httpMethod, "PUT", row.host)
            XCTAssertEqual(put.url?.path(), "/v1/runs/run-t", row.host)
            XCTAssertEqual(put.url?.query(), row.query, row.host)
            XCTAssertEqual(try encoder.encode(try ChatCompletionRequest(sent)), plainBody, row.host)
        }
        let body = String(decoding: plainBody, as: UTF8.self)
        XCTAssertFalse(body.contains("tools"), "the body names tools")
        XCTAssertFalse(body.contains("draw"), "the body names drawing")
    }
}
