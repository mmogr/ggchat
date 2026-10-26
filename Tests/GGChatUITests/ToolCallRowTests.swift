import GGChatCore
import XCTest

@testable import GGChatUI

/// What is drawn of the tools a finished reply called: one collapsed row
/// each, under the reply, saying the tool, whose it is and whether it
/// failed, in words as well as the mark.
@MainActor
final class ToolCallRowTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private static let search = ToolExchange(
        callID: "c1", name: "3:tavily_search", arguments: #"{"query":"cargo lock v4"}"#,
        server: "Tavily Web Search")
    private static let draw = ToolExchange(
        callID: "c2", name: "builtin:generate_image", arguments: #"{"prompt":"a fox"}"#)

    /// The names of the views a view is built from that start with one of
    /// `names`, in the order it draws them. A view found is not looked into.
    private func drawn(_ names: [String], in value: Any, depth: Int = 0) -> [String] {
        let name = String(describing: type(of: value))
        if let found = names.first(where: name.hasPrefix) { return [found] }
        guard depth < 40 else { return [] }
        return Mirror(reflecting: value).children.flatMap { drawn(names, in: $0.value, depth: depth + 1) }
    }

    /// The exchanges a view's `ForEach` draws a row for, or nil when it
    /// draws none.
    private func rows(in value: Any, depth: Int = 0) -> [ToolExchange]? {
        if String(describing: type(of: value)).hasPrefix("ForEach") {
            return Mirror(reflecting: value).children.first { $0.label == "data" }?.value as? [ToolExchange]
        }
        guard depth < 40 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = rows(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Every row has the tool's symbol, and one that failed the warning
    /// mark beside it. VoiceOver hears the tool, whose it is when known,
    /// "failed" when it did, and whether the row is open.
    func testTheRowSaysTheToolWhoseItIsAndWhetherItFailed() {
        XCTAssertEqual(ToolCallRow.symbol, "wrench.and.screwdriver")
        XCTAssertEqual(ToolCallRow.failedSymbol, "exclamationmark.triangle.fill")

        var failed = Self.search
        failed.result = "usage limit reached"
        failed.failed = true
        XCTAssertEqual(
            ToolCallRow.label(for: failed, expanded: false),
            "Tool call, tavily_search on Tavily Web Search, failed, collapsed")
        failed.failed = false
        XCTAssertEqual(
            ToolCallRow.label(for: failed, expanded: true), "Tool call, tavily_search on Tavily Web Search, expanded")
        failed.failed = nil
        XCTAssertEqual(
            ToolCallRow.label(for: failed, expanded: false), "Tool call, tavily_search on Tavily Web Search, collapsed")
        XCTAssertEqual(
            ToolCallRow.label(for: Self.draw, expanded: false), "Tool call, generate_image on gglib, collapsed")
        let plain = ToolExchange(callID: "c3", name: "plot_chart", arguments: "{}", failed: true)
        XCTAssertEqual(ToolCallRow.label(for: plain, expanded: false), "Tool call, plot_chart, failed, collapsed")

        // A label is not looked into, so an image found is the mark.
        func marks() -> Int {
            drawn(["Label", "Image"], in: ToolCallRow(exchange: failed).body).count(where: { $0 == "Image" })
        }
        failed.failed = true
        XCTAssertEqual(marks(), 1)
        for unknownOrFine in [false, nil] as [Bool?] {
            failed.failed = unknownOrFine
            XCTAssertEqual(marks(), 0, "\(unknownOrFine as Any)")
        }
    }

    /// A reply a run with a server's tool and gglib's own wrote keeps both
    /// calls, the server's named and its failure said, and the stored
    /// reply draws one row for each, in order, under its words; its
    /// question draws none, and nor does a reply a hub is still writing.
    func testEachToolAStoredReplyCalledIsOneRowAndAQuestionHasNone() async throws {
        let hub = FakeRunHub(frames: [
            [.tool("Tavily Search: cargo lock v4"), .toolCalled(Self.search)],
            [.toolEnded("c1"), .toolAnswered(callID: "c1", text: "usage limit reached", failed: true)],
            [.tool("Generate Image"), .toolCalled(Self.draw)],
            [.toolEnded("c2"), .toolAnswered(callID: "c2", text: "Drew 1 image", failed: false)],
            [.delta("Pin the version.")],
        ])
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: Drawing.offersTavily)
        XCTAssertTrue(model.send("what is new in cargo?", images: []))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        let reply = messages[1]
        XCTAssertEqual(reply.exchanges.map(\.heading), ["tavily_search · Tavily Web Search", "generate_image · gglib"])
        XCTAssertEqual(reply.exchanges.map(\.failed), [true, false])

        let names = ["MarkdownBlocksView", "ToolCallRows"]
        func row(_ message: Message) -> MessageRow {
            MessageRow(message: message, showsEnding: false, advice: nil, writingLine: nil)
        }
        XCTAssertEqual(drawn(names, in: row(reply).body), ["MarkdownBlocksView", "ToolCallRows"])
        XCTAssertEqual(rows(in: ToolCallRows(message: reply).body), reply.exchanges)

        var question = messages[0]
        question.exchanges = reply.exchanges
        XCTAssertNil(rows(in: ToolCallRows(message: question).body), "a question drew a tool's row")
        var none = reply
        none.exchanges = []
        XCTAssertEqual(rows(in: ToolCallRows(message: none).body), [])
        var writing = reply
        writing.runID = "r1"
        XCTAssertNil(rows(in: ToolCallRows(message: writing).body), "a reply still being written drew its rows")
    }
}
