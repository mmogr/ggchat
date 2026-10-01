import GGChatCore
import XCTest

@testable import GGChatUI

final class MarkdownBlockViewTests: XCTestCase {
    private let table = MarkdownTable(
        alignments: [.leading, .trailing],
        header: ["Model", "Context"],
        rows: [["Qwen", "32k"], ["Llama", ""]])

    /// Whether `value` holds a `T` among the views it is built from. A view
    /// built by a `switch` keeps only the branch taken, so this sees the view
    /// a block is drawn with and none of the others.
    private func holds<T>(_: T.Type, in value: Any, depth: Int = 0) -> Bool {
        if value is T { return true }
        guard depth < 24 else { return false }
        return Mirror(reflecting: value).children.contains { holds(T.self, in: $0.value, depth: depth + 1) }
    }

    @MainActor
    func testATableBlockIsDrawnAsATableAndNotAsCode() {
        let body = MarkdownBlockView(block: .table(table)).body
        XCTAssertTrue(holds(TableBlockView.self, in: body))
        XCTAssertFalse(holds(CodeBlockView.self, in: body))
    }

    @MainActor
    func testACodeBlockIsStillDrawnAsCode() {
        let body = MarkdownBlockView(block: .code(language: "swift", text: "let a = 1")).body
        XCTAssertTrue(holds(CodeBlockView.self, in: body))
        XCTAssertFalse(holds(TableBlockView.self, in: body))
    }

    @MainActor
    func testVoiceOverReadsATableARowAtATime() {
        XCTAssertEqual(
            TableBlockView.spokenRows(table),
            ["Model, Context", "Model: Qwen, Context: 32k", "Model: Llama"])
        let unnamed = MarkdownTable(alignments: [nil, nil], header: ["", "Size"], rows: [["a", "1"]])
        XCTAssertEqual(TableBlockView.spokenRows(unnamed), ["Size", "a, Size: 1"])
    }
}
