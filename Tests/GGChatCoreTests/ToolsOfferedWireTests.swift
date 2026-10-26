import Foundation
import XCTest

@testable import GGChatCore

/// A paired Mac that offers its MCP servers' tools: what its answer about
/// drawing says of them, and how a run that carries them is put.
final class ToolsOfferedWireTests: XCTestCase {
    /// One row of the query table: the servers the request names, whether
    /// it draws and with which image model, the host it is put to, and the
    /// query it is put with.
    private struct Row {
        var host: String
        var servers: [Int64]
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
            + #""mcp_servers":[{"id":3,"name":"tavily"}]}"#
        let refused = try drawing(cannot)
        XCTAssertFalse(refused.available)
        XCTAssertEqual(refused.mcpServers, [OfferedServer(id: 3, name: "tavily")])
        XCTAssertTrue(refused.offersTools, "a Mac that cannot draw did not offer its servers")
        let two =
            #"{"available":true,"model":"flux-dev","mcp_servers":[{"id":3,"name":"tavily"},{"id":4,"name":"fs"}]}"#
        XCTAssertTrue(try drawing(two).offersTools)

        for none in [
            #"{"available":true,"model":"flux-dev"}"#, #"{"available":true,"model":"flux-dev","mcp_servers":null}"#,
            #"{"available":true,"model":"flux-dev","mcp_servers":[]}"#,
        ] {
            XCTAssertFalse(try drawing(none).offersTools, none)
        }
        XCTAssertNil(try drawing(#"{"available":false}"#).mcpServers)
    }

    /// Two servers the Mac lists under one name are two servers, each by its
    /// own id, in the Mac's order, and neither is folded into the other.
    func testTwoServersOfOneNameAreReadAsTwo() throws {
        let body =
            #"{"available":true,"mcp_servers":[{"id":4,"name":"fs"},{"id":9,"name":"fs"},{"id":3,"name":"tavily"}]}"#
        let read = try JSONDecoder().decode(Drawing.self, from: Data(body.utf8))
        XCTAssertEqual(read.mcpServers?.map(\.id), [4, 9, 3])
        XCTAssertEqual(read.mcpServers?.map(\.name), ["fs", "fs", "tavily"])
        XCTAssertEqual(Set(read.mcpServers ?? []).count, 3, "two servers of one name read as one")
    }

    /// A run that names servers is put as a chat run naming them by id,
    /// sorted and joined by a bare comma, and adds `draw=true` only when it
    /// draws, with the chosen image model only then. A run that draws and
    /// names none is put with `tools=none`, and one that does neither has no
    /// query. The body is the same in every one, and says nothing of tools.
    func testARunWithToolsIsPutWithThemAndDrawsOnlyWhenItDraws() async throws {
        func request(servers: [Int64], draws: Bool, chosen: UInt64?) -> ChatRequest {
            ChatRequest(
                model: "Qwen3.8-27B",
                messages: [Message(role: .user, content: "what is new?", createdAt: Date(timeIntervalSince1970: 0))],
                returnProgress: true, draws: draws, imageModelID: chosen, toolServers: servers)
        }
        let table = [
            Row(host: "plain.offered.test", servers: [], draws: false),
            Row(host: "unchosen.plain.offered.test", servers: [], draws: false, chosen: 7),
            Row(host: "none.draws.offered.test", servers: [], draws: true, query: "kind=chat&tools=none&draw=true"),
            Row(
                host: "none.chosen.offered.test", servers: [], draws: true, chosen: 7,
                query: "kind=chat&tools=none&draw=true&image_model=7"),
            Row(host: "one.offered.test", servers: [3], draws: false, query: "kind=chat&tools=3"),
            Row(host: "two.offered.test", servers: [3, 7], draws: false, query: "kind=chat&tools=3,7"),
            Row(host: "unsorted.offered.test", servers: [7, 3, 7], draws: false, query: "kind=chat&tools=3,7"),
            Row(
                host: "one.unchosen.offered.test", servers: [3], draws: false, chosen: 7,
                query: "kind=chat&tools=3"),
            Row(
                host: "one.chosen.offered.test", servers: [3], draws: true, chosen: 7,
                query: "kind=chat&tools=3&draw=true&image_model=7"),
        ]
        var script = RunHub.Script(frames: [], ending: RunHub.report("run-t", "completed", lastSeq: 0))
        script.put = (201, RunHub.report("run-t", "queued", lastSeq: 0))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let plainBody = try encoder.encode(
            try ChatCompletionRequest(request(servers: [], draws: false, chosen: nil)))
        for row in table {
            RunHub.serve(script, at: row.host)
            let sent = request(servers: row.servers, draws: row.draws, chosen: row.chosen)
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
