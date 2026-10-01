import XCTest

@testable import GGChatCore

final class LiveMarkdownTests: XCTestCase {
    /// Feeds `text` a few characters at a time, as tokens arrive, and checks
    /// each step against a parse of the whole text so far.
    private func assertEveryPrefixParsesAsTheWholeDoes(
        _ text: String, step: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        let characters = Array(text)
        var live = LiveMarkdown()
        var count = 0
        while true {
            let prefix = String(characters[..<count])
            live.update(to: prefix)
            let whole = MarkdownBlocks.parse(prefix)
            guard live.blocks == whole else {
                return XCTFail(
                    "at \(prefix.debugDescription):\n\(live.blocks)\nis not\n\(whole)", file: file, line: line)
            }
            if count == characters.count { return }
            count = min(characters.count, count + step)
        }
    }

    func testEveryPrefixOfASampleReplyParsesAsTheWholeDoes() {
        for sample in LiveMarkdownSamples.replies {
            for step in [1, 3, 7] {
                assertEveryPrefixParsesAsTheWholeDoes(sample, step: step)
            }
        }
    }

    func testEveryPrefixOfRandomMarkdownParsesAsTheWholeDoes() {
        var random = LiveMarkdownSamples.Random(seed: 87)
        for _ in 0..<300 {
            let lines = (0..<(3 + random.next(20))).map { _ in
                LiveMarkdownSamples.lines[random.next(LiveMarkdownSamples.lines.count)]
            }
            let text = lines.joined(separator: "\n") + (random.next(2) == 0 ? "\n" : "")
            assertEveryPrefixParsesAsTheWholeDoes(text, step: 1 + random.next(4))
        }
    }

    func testACodeFenceStillOpenAtTheEndStaysOpen() {
        var live = LiveMarkdown()
        live.update(to: "Intro.\n\n```swift\nlet a = 1\n")
        XCTAssertEqual(live.blocks.last, .code(language: "swift", text: "let a = 1"))
        live.update(to: "Intro.\n\n```swift\nlet a = 1\n\nNot prose yet\n")
        XCTAssertEqual(live.blocks.count, 2)
        XCTAssertEqual(live.blocks.last, .code(language: "swift", text: "let a = 1\n\nNot prose yet"))
        live.update(to: "Intro.\n\n```swift\nlet a = 1\n\nNot prose yet\n```\n\nProse.")
        XCTAssertEqual(live.blocks.count, 3)
        guard case .paragraph = live.blocks.last else { return XCTFail("\(live.blocks)") }
    }

    func testATableStillOpenAtTheEndStaysOpen() {
        var live = LiveMarkdown()
        live.update(to: "| a | b |\n|---|---|\n| 1 | 2 |\n")
        live.update(to: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 |")
        guard case .table(let table) = live.blocks.last else { return XCTFail("\(live.blocks)") }
        XCTAssertEqual(table.rows.map { $0.map { String($0.characters) } }, [["1", "2"], ["3", ""]])
        live.update(to: "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nAfter.")
        XCTAssertEqual(live.blocks.count, 2)
        guard case .table(let grown) = live.blocks.first else { return XCTFail("\(live.blocks)") }
        XCTAssertEqual(grown.rows.count, 2)
    }

    func testADefinitionAfterAParagraphStillMakesItALink() {
        var live = LiveMarkdown()
        live.update(to: "See [the docs].\n\nMore.\n\nAnd more.\n")
        live.update(to: "See [the docs].\n\nMore.\n\nAnd more.\n\n[the docs]: https://example.com\n")
        guard case .paragraph(let first) = live.blocks.first else { return XCTFail("\(live.blocks)") }
        XCTAssertTrue(first.runs.contains { $0.link == URL(string: "https://example.com") })
    }

    func testTextThatDoesNotCarryOnIsParsedAfresh() {
        var live = LiveMarkdown()
        live.update(to: "# One\n\nfirst\n\nsecond\n\n")
        live.update(to: "- two\n")
        XCTAssertEqual(live.blocks, MarkdownBlocks.parse("- two\n"))
        // A definition in such text is looked for from its start, not from
        // where the longer text before it ended.
        live.update(to: String(repeating: "A longer first reply.\n", count: 8))
        for text in ["Intro.\n\n[a]: /u\n\nSee [a].\n", "Intro.\n\n[a]: /u\n\nSee [a].\n\nAnd [a].\n"] {
            live.update(to: text)
            XCTAssertEqual(live.blocks, MarkdownBlocks.parse(text), text.debugDescription)
        }
    }

    func testABlockOverlappingTheOneBeforeItIsNoBoundary() {
        // A table that starts on the line of the paragraph above it, and a
        // block whose lines are unknown, are both passed over for the clean
        // boundary before them.
        let overlapping = LiveMarkdown.lastCleanStart([(1, 1), (1, 4), (6, 6)])
        XCTAssertEqual(overlapping?.index, 2)
        XCTAssertEqual(overlapping?.line, 6)
        let unknown = LiveMarkdown.lastCleanStart([(1, 2), (4, 5), nil, (8, 8)])
        XCTAssertEqual(unknown?.index, 1)
        XCTAssertEqual(unknown?.line, 4)
        XCTAssertNil(LiveMarkdown.lastCleanStart([(1, 3), (3, 4)]))
    }

    func testOnlyALabelAtTheStartOfALineMayBeADefinition() {
        let cases: [(String, Bool)] = [
            ("[docs]: https://example.com", true),
            ("> - [docs]: /a", true),
            ("1. [ ] [docs]: /a", true),
            ("[two\nlines]: /a", true),
            ("[a\n]: /a", true),
            ("[a\nb\nc]: /a", true),
            ("[a\\]b]: /a", true),
            ("def f(a: int) -> list[int]:", false),
            ("for x in items[1:]:", false),
            ("see [docs]: /a", false),
            ("\\[docs]: /a", false),
            ("[a]b]: /a", false),
            ("[two\n\nparagraphs]: /a", false),
        ]
        for (text, expected) in cases {
            var text = text
            let found = text.withUTF8 { MarkdownScan.mayReachAcrossBlocks($0, from: 0) }
            XCTAssertEqual(found, expected, text.debugDescription)
        }
    }

    /// The point of it: a token parses the text after the settled blocks, so
    /// the parsing per token stays the size of the last block or two however
    /// long the reply grows.
    func testSettledBlocksAreNotParsedAgain() {
        let reply = (1...50).map(LiveMarkdownSamples.step).joined()
        XCTAssertGreaterThan(reply.utf8.count, 12_000)
        let characters = Array(reply)
        let meter = ParseMeter()
        var live = LiveMarkdown()
        var most = 0
        ParseMeter.$current.withValue(meter) {
            for end in stride(from: 4, through: characters.count, by: 4) {
                let before = meter.bytes
                live.update(to: String(characters[..<end]))
                most = max(most, meter.bytes - before)
            }
            live.update(to: reply)
        }
        XCTAssertEqual(live.blocks, MarkdownBlocks.parse(reply))
        XCTAssertGreaterThanOrEqual(meter.bytes, reply.utf8.count, "every byte was parsed at least once")
        XCTAssertLessThan(most, 1_000, "a token parsed \(most) bytes of a \(reply.utf8.count)-byte reply")
    }
}
