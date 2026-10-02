import XCTest

@testable import GGChatCore

final class MarkdownTests: XCTestCase {
    func testParagraphCodeParagraph() {
        let blocks = MarkdownBlocks.parse(MockProvider.sampleScript.text)
        XCTAssertEqual(blocks.count, 3)
        guard case .code(let language, let text) = blocks[1] else { return XCTFail("\(blocks[1])") }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(text.hasPrefix("let text = try String"))
        XCTAssertFalse(text.hasSuffix("\n"))
    }

    func testUnterminatedFenceIsStillACodeBlock() {
        let blocks = MarkdownBlocks.parse("Before\n\n```python\nprint(1)\nprint(2)")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1], .code(language: "python", text: "print(1)\nprint(2)"))
    }

    func testInlineStrongEmphasisSurvives() throws {
        let blocks = MarkdownBlocks.parse("some **bold** words")
        guard case .paragraph(let text) = try XCTUnwrap(blocks.first) else { return XCTFail("unexpected block shape") }
        XCTAssertEqual(String(text.characters), "some bold words")
        XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    func testListsHeadingsQuotesAndRules() {
        let blocks = MarkdownBlocks.parse("# Title\n\n- a\n- b\n\n1. one\n2. two\n\n> quoted\n\n---\n")
        XCTAssertEqual(blocks.count, 5)
        guard case .heading(let level, _) = blocks[0] else { return XCTFail("unexpected block shape") }
        XCTAssertEqual(level, 1)
        guard case .list(let ordered, let items) = blocks[1] else { return XCTFail("unexpected block shape") }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items.map { String($0.characters) }, ["a", "b"])
        guard case .list(let ordered2, _) = blocks[2] else { return XCTFail("unexpected block shape") }
        XCTAssertTrue(ordered2)
        guard case .quote(let inner) = blocks[3] else { return XCTFail("unexpected block shape") }
        XCTAssertEqual(inner.count, 1)
        guard case .paragraph(let quoted) = inner[0] else { return XCTFail("unexpected block shape") }
        XCTAssertEqual(String(quoted.characters), "quoted", "the quote marker is not part of the text")
        XCTAssertEqual(blocks[4], .thematicBreak)
    }

    func testEmptyTextGivesNoBlocks() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
    }

    func testASoftBreakReadsAsASpace() {
        XCTAssertEqual(characters(ofParagraph: "one\ntwo"), "one two")
        // Every other block whose text is inline markdown: a setext heading,
        // a list item and a quote.
        let blocks = MarkdownBlocks.parse("three\nfour\n===\n\n- five\n  six\n\n> seven\n> eight")
        XCTAssertEqual(blocks.count, 3)
        guard case .heading(_, let heading) = blocks[0] else { return XCTFail("\(blocks)") }
        XCTAssertEqual(String(heading.characters), "three four")
        guard case .list(_, let items) = blocks[1] else { return XCTFail("\(blocks)") }
        XCTAssertEqual(items.map { String($0.characters) }, ["five six"])
        guard case .quote(let inner) = blocks[2], inner.count == 1, case .paragraph(let quoted) = inner[0] else {
            return XCTFail("\(blocks)")
        }
        XCTAssertEqual(String(quoted.characters), "seven eight")
    }

    func testASoftBreakBesideCodeEmphasisAndALinkReadsAsASpace() {
        let text = paragraph("`code`\n*em*\n[link](https://example.com)\nend *one\ntwo*")
        XCTAssertEqual(String(text.characters), "code em link end one two")
        // Each style stays on its own words, and the space a break became is
        // in none of them but the emphasis it was inside.
        func words(where styled: (AttributedString.Runs.Run) -> Bool) -> [String] {
            text.runs.filter(styled).map { String(text[$0.range].characters) }
        }
        XCTAssertEqual(words { $0.inlinePresentationIntent == .code }, ["code"])
        XCTAssertEqual(words { $0.inlinePresentationIntent == .emphasized }, ["em", "one two"])
        XCTAssertEqual(words { $0.link == URL(string: "https://example.com") }, ["link"])
    }

    func testAHardBreakIsANewline() {
        XCTAssertEqual(characters(ofParagraph: "one  \ntwo"), "one\ntwo", "two trailing spaces")
        XCTAssertEqual(characters(ofParagraph: "one\\\ntwo"), "one\ntwo", "a trailing backslash")
        XCTAssertEqual(characters(ofParagraph: "*one  \ntwo*"), "one\ntwo", "inside emphasis")
    }

    func testPunctuationReadsAsTyped() {
        let typed = #"wait --- what -- "this" isn't..."#
        XCTAssertEqual(characters(ofParagraph: typed), typed)
    }

    /// The one paragraph `markdown` parses into, or a failure and nothing.
    private func paragraph(_ markdown: String, line: UInt = #line) -> AttributedString {
        let blocks = MarkdownBlocks.parse(markdown)
        guard blocks.count == 1, case .paragraph(let text) = blocks[0] else {
            XCTFail("not one paragraph: \(blocks)", line: line)
            return AttributedString()
        }
        return text
    }

    private func characters(ofParagraph markdown: String, line: UInt = #line) -> String {
        String(paragraph(markdown, line: line).characters)
    }
}
