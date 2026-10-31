import XCTest

@testable import GGChatCore

/// What a reply keeps of each tool it called beyond the call and its answer:
/// the MCP server the tool is one of, from `tool_call_start`'s `server`,
/// whether it failed, from `tool_call_complete`'s `result.success`, and the
/// ids of the images it made, from its `result.images`. None is sent back,
/// and a list kept before any of them still reads.
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

    /// A list kept before the three fields, which has none of their keys,
    /// reads with no server, not known to have failed and its images not
    /// known, rather than failing to read and being kept as none. One kept
    /// with them reads them back.
    func testAnExchangeKeptBeforeItsServerAndFailureReadsWithNeither() throws {
        let kept = #"[{"callID":"c1","name":"builtin:generate_image","arguments":"{}","result":"Drew 1 image"}]"#
        let read = try JSONDecoder().decode([ToolExchange].self, from: Data(kept.utf8))
        XCTAssertEqual(
            read,
            [ToolExchange(callID: "c1", name: "builtin:generate_image", arguments: "{}", result: "Drew 1 image")])
        XCTAssertNil(read.first?.server)
        XCTAssertNil(read.first?.failed)
        XCTAssertNil(read.first?.images)

        let later = [
            ToolExchange(
                callID: "c2", name: "3:tavily_search", arguments: "{}", result: "no", server: "Tavily Web Search",
                failed: true, images: []),
            ToolExchange(callID: "c3", name: "plot_chart", arguments: "{}", result: "a chart", images: ["a1", "a2"]),
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

    /// The request after a reply that called a server's tool, one that
    /// failed and one that made an image, is byte for byte the one it would
    /// be if none of that were known: the call is its id, name and
    /// arguments, and the answer its words.
    func testTheRequestNeverSaysAToolsServerOrWhetherItFailed() throws {
        func request(server: String?, failed: Bool?, images: [String]? = nil) -> ChatRequest {
            var reply = Message(role: .assistant, content: "Pin the version.", createdAt: .distantPast)
            reply.exchanges = [
                ToolExchange(
                    callID: "c4", name: "3:tavily_search", arguments: #"{"query":"cargo lock v4"}"#,
                    result: "usage limit reached", server: server, failed: failed, images: images)
            ]
            let question = Message(role: .user, content: "what is new?", createdAt: .distantPast)
            return ChatRequest(model: "m", messages: [question, reply], replaysToolCalls: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let known = try encoder.encode(
            try ChatCompletionRequest(request(server: "Tavily Web Search", failed: true, images: ["made-by-c4"])))
        let unknown = try encoder.encode(try ChatCompletionRequest(request(server: nil, failed: nil)))
        XCTAssertEqual(known, unknown)
        let body = String(decoding: known, as: UTF8.self)
        XCTAssertTrue(body.contains("tool_calls"), "the call was not sent at all")
        XCTAssertFalse(body.contains("server"), body)
        XCTAssertFalse(body.contains("Tavily"), body)
        XCTAssertFalse(body.contains("failed"), body)
        XCTAssertFalse(body.contains("made-by-c4"), body)
        XCTAssertFalse(body.contains("images"), body)
    }

    /// Each answered call keeps the ids of the images it made, from its
    /// `tool_call_complete`, and one that made none keeps none, so a
    /// reply's images say which call made which. A call never answered
    /// does not say. Images are put on the call they name, each once and
    /// after any it has; ones for a call that is not held, or named for no
    /// call, change nothing; and a later reading of a call that does not
    /// say keeps what it was known to have made.
    func testEachAnsweredCallKeepsTheImagesItMade() throws {
        let exchanges = try recorded()
        XCTAssertEqual(exchanges.map(\.callID), ["c1", "c2", "c3", "c4"])
        XCTAssertEqual(
            exchanges.map(\.images),
            [[], nil, ["0a7441cf32e72812c1c5010b095a68b98c2384d127a42c4158c805032a47b6fe"], []],
            "c2 was never answered")

        func image(_ id: String) -> ImageRef { ImageRef(id: id, mime: ImageRef.png, width: 8, height: 8) }
        var held = [ToolExchange(callID: "c1", name: "draw", arguments: "{}")]
        held.take(.toolAnswered(callID: "c1", text: "Drew 2 images"))
        held.take(.images([image("a1"), image("a2")], callID: "c1"))
        held.take(.images([image("a2"), image("a3")], callID: "c1"))
        held.take(.images([image("b1")], callID: "c9"))
        held.take(.images([image("b2")]))
        XCTAssertEqual(held.first?.images, ["a1", "a2", "a3"])
        held.take(.toolAnswered(callID: "c1", text: "Drew 3 images"))
        XCTAssertEqual(held.first?.images, ["a1", "a2", "a3"], "a second answer forgot the images")

        held.merge([ToolExchange(callID: "c1", name: "draw", arguments: #"{"again":true}"#)])
        XCTAssertEqual(held.first?.arguments, #"{"again":true}"#)
        XCTAssertEqual(held.first?.images, ["a1", "a2", "a3"], "a later reading that does not say dropped them")
        held.merge([ToolExchange(callID: "c1", name: "draw", arguments: "{}", result: "Drew", images: ["a9"])])
        XCTAssertEqual(held.first?.images, ["a9"])
    }
}
