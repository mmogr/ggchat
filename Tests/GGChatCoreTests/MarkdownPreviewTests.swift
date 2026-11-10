import XCTest

@testable import GGChatCore

/// What a long-pressed message lifts: whole blocks from the top, up to a
/// budget of characters.
final class MarkdownPreviewTests: XCTestCase {
    private func paragraph(_ length: Int) -> String {
        String(repeating: "a", count: length)
    }

    func testAShortMessageLiftsWhole() {
        let blocks = MarkdownBlocks.parse("# News\n\nOne line.\n\n- a\n- b")
        let preview = MarkdownPreview(blocks)
        XCTAssertEqual(preview.blocks, blocks)
        XCTAssertFalse(preview.isCut)
    }

    func testALongReplyLiftsOnlyTheBlocksThatFitTheBudget() {
        let text = (0..<10).map { _ in paragraph(200) }.joined(separator: "\n\n")
        let preview = MarkdownPreview(MarkdownBlocks.parse(text), budget: 700)
        XCTAssertEqual(preview.blocks.count, 3)
        XCTAssertTrue(preview.isCut)
    }

    func testAFirstBlockOverTheBudgetIsStillTaken() {
        let text = paragraph(2_000) + "\n\nSecond."
        let preview = MarkdownPreview(MarkdownBlocks.parse(text), budget: 700)
        XCTAssertEqual(preview.blocks.count, 1)
        XCTAssertTrue(preview.isCut)
    }

    func testCodeListsQuotesAndTablesCountTheCharactersTheyShow() {
        let blocks = MarkdownBlocks.parse(
            "```\nabcd\n```\n\n- ab\n- cd\n\n> abcd\n\n| a | b |\n|---|---|\n| c | d |\n\n---")
        XCTAssertEqual(blocks.map(MarkdownPreview.characters(in:)), [4, 4, 4, 4, 0])
    }

    func testNoBlocksLiftNothing() {
        let preview = MarkdownPreview([])
        XCTAssertEqual(preview.blocks, [])
        XCTAssertFalse(preview.isCut)
    }
}
