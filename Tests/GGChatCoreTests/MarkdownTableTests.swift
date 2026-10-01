import XCTest

@testable import GGChatCore

private struct NotATable: Error {}

final class MarkdownTableTests: XCTestCase {
    private func table(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> MarkdownTable {
        let blocks = MarkdownBlocks.parse(text)
        XCTAssertEqual(blocks.count, 1, "\(blocks)", file: file, line: line)
        guard case .table(let table) = blocks.first else {
            XCTFail("not a table: \(blocks)", file: file, line: line)
            throw NotATable()
        }
        return table
    }

    private func plain(_ cells: [AttributedString]) -> [String] {
        cells.map { String($0.characters) }
    }

    func testATableParsesIntoItsHeaderAlignmentsAndRows() throws {
        let table = try table(
            """
            | Model | Context | Speed | Notes |
            |:------|:-------:|------:|-------|
            | Qwen  | 32k     | fast  | new   |
            | Llama | 8k      | slow  | old   |
            """)
        XCTAssertEqual(table.alignments, [.leading, .center, .trailing, nil])
        XCTAssertEqual(plain(table.header), ["Model", "Context", "Speed", "Notes"])
        XCTAssertEqual(table.rows.map(plain), [["Qwen", "32k", "fast", "new"], ["Llama", "8k", "slow", "old"]])
    }

    func testACellKeepsItsInlineMarkdown() throws {
        let table = try table(
            """
            | Name | Where |
            |------|-------|
            | **bold** and *soft* | `a \\| b` at [the site](https://example.com) |
            """)
        let name = table.rows[0][0]
        XCTAssertEqual(String(name.characters), "bold and soft")
        XCTAssertTrue(name.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(name.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
        let place = table.rows[0][1]
        XCTAssertEqual(String(place.characters), "a | b at the site", "an escaped pipe is a pipe inside its cell")
        XCTAssertTrue(place.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        XCTAssertTrue(place.runs.contains { $0.link == URL(string: "https://example.com") })
    }

    func testEveryRowHasACellPerColumn() throws {
        let table = try table(
            """
            | a | b |
            |---|---|
            | only |
            | 1 | 2 | 3 |
            """)
        XCTAssertEqual(table.rows.map(plain), [["only", ""], ["1", "2"]])
    }

    func testACaretCellIsKeptAsWritten() throws {
        let table = try table(
            """
            | a | b |
            |---|---|
            | 1 | 2 |
            | ^ | 3 |
            """)
        XCTAssertEqual(table.rows.map(plain), [["1", "2"], ["^", "3"]])
    }

    func testATableUnderAParagraphLineTakesOnlyItsOwnLines() {
        let blocks = MarkdownBlocks.parse("Intro line\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter")
        XCTAssertEqual(blocks.count, 3, "\(blocks)")
        guard case .paragraph(let intro) = blocks[0], case .table(let table) = blocks[1],
            case .paragraph(let after) = blocks[2]
        else { return XCTFail("\(blocks)") }
        XCTAssertEqual(String(intro.characters), "Intro line")
        XCTAssertEqual(plain(table.header), ["a", "b"])
        XCTAssertEqual(String(after.characters), "After")
    }

    func testTableTextThatIsNotATableIsKeptAsAParagraph() {
        // A delimiter row with fewer cells than the header, and pipes with no
        // delimiter row at all: neither is a table, and no line is dropped.
        let cases = [
            ("| a | b |\n| --- |\n| 1 | 2 |", ["| a | b |", "| 1 | 2 |"]),
            ("a | b\n1 | 2", ["a | b", "1 | 2"]),
        ]
        for (text, lines) in cases {
            let blocks = MarkdownBlocks.parse(text)
            guard blocks.count == 1, case .paragraph(let paragraph) = blocks[0] else {
                XCTFail("\(text.debugDescription) gave \(blocks)")
                continue
            }
            for line in lines {
                XCTAssertTrue(String(paragraph.characters).contains(line), "\(line) in \(paragraph)")
            }
        }
    }
}
