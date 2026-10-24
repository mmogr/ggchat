import XCTest

@testable import GGChatCore

/// What a reply keeps of each tool it called beyond the call and its answer:
/// the MCP server the tool is one of, from `tool_call_start`'s `server`, and
/// whether it failed, from `tool_call_complete`'s `result.success`. Neither
/// is sent back, and a list kept before either still reads.
final class ToolExchangeWireTests: XCTestCase {
    /// The exchanges the recorded agent run leaves, as a reply being read
    /// gathers them.
    private func recorded() throws -> [ToolExchange] {
        let lines = String(decoding: try Fixtures.data("gglib-agent-run-events.jsonl"), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        var exchanges: [ToolExchange] = []
        for line in lines {
            for event in OpenAICompatibleProvider.agentEvents(SSEEvent(data: line)) { exchanges.take(event) }
        }
        return exchanges
    }

    /// A list kept before the two fields, which has neither key, reads with
    /// no server and not known to have failed, rather than failing to read
    /// and being kept as none. One kept with them reads them back.
    func testAnExchangeKeptBeforeItsServerAndFailureReadsWithNeither() throws {
        let kept = #"[{"callID":"c1","name":"builtin:generate_image","arguments":"{}","result":"Drew 1 image"}]"#
        let read = try JSONDecoder().decode([ToolExchange].self, from: Data(kept.utf8))
        XCTAssertEqual(
            read,
            [ToolExchange(callID: "c1", name: "builtin:generate_image", arguments: "{}", result: "Drew 1 image")])
        XCTAssertNil(read.first?.server)
        XCTAssertNil(read.first?.failed)

        let later = [
            ToolExchange(
                callID: "c2", name: "3:tavily_search", arguments: "{}", result: "no", server: "Tavily Web Search",
                failed: true)
        ]
        XCTAssertEqual(try JSONDecoder().decode([ToolExchange].self, from: try JSONEncoder().encode(later)), later)
    }

    /// A call whose start names its server keeps it, and one gglib calls its
    /// own keeps none. An answer that says it did not succeed is one that
    /// failed, one that says it did is not, and one that does not say is
    /// not known either way.
    func testAToolsServerAndItsFailureLandOnItsExchange() throws {
        let exchanges = try recorded()
        XCTAssertEqual(exchanges.map(\.callID), ["c1", "c2", "c3", "c4"])
        XCTAssertEqual(exchanges.map(\.server), [nil, nil, nil, "Tavily Web Search"])
        XCTAssertEqual(exchanges.map(\.failed), [false, nil, false, true], "c2 was never answered")
        XCTAssertEqual(exchanges.last?.result, "Tavily answered 432: usage limit reached")

        var unsaid = [ToolExchange(callID: "c9", name: "3:tavily_search", arguments: "{}")]
        let silent =
            #"{"type":"tool_call_complete","result":{"tool_call_id":"c9","content":"fine"}}"#
        for event in OpenAICompatibleProvider.agentEvents(SSEEvent(data: silent)) { unsaid.take(event) }
        XCTAssertEqual(unsaid.first?.result, "fine")
        XCTAssertNil(unsaid.first?.failed, "an answer that does not say was taken as one that did")
    }

    /// The request after a reply that called a server's tool, and one that
    /// failed, is byte for byte the one it would be if neither were known:
    /// the call is its id, name and arguments, and the answer its words.
    func testTheRequestNeverSaysAToolsServerOrWhetherItFailed() throws {
        func request(server: String?, failed: Bool?) -> ChatRequest {
            var reply = Message(role: .assistant, content: "Pin the version.", createdAt: .distantPast)
            reply.exchanges = [
                ToolExchange(
                    callID: "c4", name: "3:tavily_search", arguments: #"{"query":"cargo lock v4"}"#,
                    result: "usage limit reached", server: server, failed: failed)
            ]
            let question = Message(role: .user, content: "what is new?", createdAt: .distantPast)
            return ChatRequest(model: "m", messages: [question, reply], replaysToolCalls: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let known = try encoder.encode(try ChatCompletionRequest(request(server: "Tavily Web Search", failed: true)))
        let unknown = try encoder.encode(try ChatCompletionRequest(request(server: nil, failed: nil)))
        XCTAssertEqual(known, unknown)
        let body = String(decoding: known, as: UTF8.self)
        XCTAssertTrue(body.contains("tool_calls"), "the call was not sent at all")
        XCTAssertFalse(body.contains("server"), body)
        XCTAssertFalse(body.contains("Tavily"), body)
        XCTAssertFalse(body.contains("failed"), body)
    }
}
