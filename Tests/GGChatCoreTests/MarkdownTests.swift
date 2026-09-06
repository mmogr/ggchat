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
}
