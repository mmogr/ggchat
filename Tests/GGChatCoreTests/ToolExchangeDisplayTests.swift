import XCTest

@testable import GGChatCore

/// What the row under a reply shows of a tool call it kept: its heading,
/// what was sent and what came back, worked out from the exchange alone.
final class ToolExchangeDisplayTests: XCTestCase {
    private let british = Locale(identifier: "en_GB")

    private func exchange(
        _ name: String, server: String? = nil, arguments: String = "{}", result: String? = nil
    ) -> ToolExchange {
        ToolExchange(callID: "c1", name: name, arguments: arguments, result: result, server: server)
    }

    /// An MCP tool is named after its server, one of gglib's own after
    /// gglib, and one this build cannot place by its name alone. The title
    /// is what follows the first `:`, or the whole name.
    func testAHeadingNamesTheToolAndWhoseItIs() {
        let search = exchange("3:tavily_search", server: "Tavily Web Search")
        XCTAssertEqual(search.title, "tavily_search")
        XCTAssertEqual(search.origin, "Tavily Web Search")
        XCTAssertEqual(search.heading, "tavily_search · Tavily Web Search")

        let draw = exchange("builtin:generate_image")
        XCTAssertEqual(draw.title, "generate_image")
        XCTAssertEqual(draw.origin, "gglib")
        XCTAssertEqual(draw.heading, "generate_image · gglib")

        let plain = exchange("plot_chart")
        XCTAssertEqual(plain.title, "plot_chart")
        XCTAssertNil(plain.origin)
        XCTAssertEqual(plain.heading, "plot_chart")

        XCTAssertEqual(exchange("3:fs:read").title, "fs:read", "a name was cut at a later colon")
        XCTAssertEqual(exchange("3:").title, "3:")
        XCTAssertEqual(exchange("3:tavily_search").heading, "tavily_search", "a server nobody named was guessed")
        XCTAssertEqual(exchange("3:tavily_search", server: "").heading, "tavily_search")
    }

    /// Arguments that are JSON are laid out over lines with their keys
    /// sorted; an empty object or array stays on one line; anything else is
    /// shown as the model wrote it.
    func testTheArgumentsAreLaidOutWhenTheyAreJSON() {
        let nested = exchange(
            "3:tavily_search", arguments: #"{"query":"swift 6.4","options":{"depth":2,"site":"a/b"}}"#)
        XCTAssertEqual(
            nested.prettyArguments,
            """
            {
              "options" : {
                "depth" : 2,
                "site" : "a/b"
              },
              "query" : "swift 6.4"
            }
            """)
        XCTAssertEqual(exchange("t", arguments: "[1,2]").prettyArguments, "[\n  1,\n  2\n]")
        XCTAssertEqual(exchange("t", arguments: "{}").prettyArguments, "{}")
        XCTAssertEqual(exchange("t", arguments: "[]").prettyArguments, "[]")
        XCTAssertEqual(exchange("t", arguments: "not json {").prettyArguments, "not json {")
        XCTAssertEqual(exchange("t", arguments: "42").prettyArguments, "42")
        XCTAssertEqual(exchange("t", arguments: "").prettyArguments, "")
    }

    /// An answer up to the limit is shown whole. A longer one is cut after
    /// the limit's characters, never inside one, and says how many more
    /// there are in the locale's digits; one more is one character.
    func testALongAnswerIsCutOnACharacterAndSaysHowMuchMore() throws {
        let exact = String(repeating: "a", count: 2_000)
        XCTAssertEqual(exchange("t", result: exact).shownResult(in: british), exact)
        XCTAssertEqual(
            exchange("t", result: exact + "b").shownResult(in: british), exact + "\n… 1 more character")

        let family = "👨‍👩‍👧‍👦"
        let flags = String(repeating: family, count: 3) + "é" + String(repeating: "x", count: 12_344)
        let cut = try XCTUnwrap(exchange("t", result: flags).shownResult(limit: 2, in: british))
        XCTAssertEqual(cut, family + family + "\n… 12,346 more characters")
        XCTAssertEqual(
            exchange("t", result: flags).shownResult(limit: 2, in: Locale(identifier: "de_DE")),
            family + family + "\n… 12.346 more characters")

        let accented = "e\u{301}e\u{301}e\u{301}"
        XCTAssertEqual(accented.count, 3)
        XCTAssertEqual(
            exchange("t", result: accented).shownResult(limit: 1, in: british), "e\u{301}\n… 2 more characters")
        XCTAssertEqual(exchange("t", result: "").shownResult(in: british), "")
    }

    /// A call nothing answered has no answer to show, and says so in its
    /// own sentence.
    func testACallNothingAnsweredHasNoAnswerToShow() {
        XCTAssertNil(exchange("3:tavily_search").shownResult(in: british))
        XCTAssertEqual(ToolExchange.noAnswer, "No answer: the reply ended before the tool answered.")
    }
}
