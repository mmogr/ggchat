import XCTest

@testable import GGChatCore

/// Math reads exactly as the model wrote it. The cases are taken from
/// replies Qwen, Gemma, gpt-oss, Mistral and DeepSeek gave to math prompts.
final class MathSpanTests: XCTestCase {
    /// Every block's text, one block or list item to a line.
    private func shown(_ markdown: String) -> String {
        func lines(_ block: MarkdownBlock) -> [String] {
            switch block {
            case .paragraph(let text), .heading(_, let text): [String(text.characters)]
            case .code(_, let text): [text]
            case .list(_, let items): items.map { String($0.characters) }
            case .quote(let inner): inner.flatMap(lines)
            case .thematicBreak: ["---"]
            case .table(let table):
                ([table.header] + table.rows).map { $0.map { String($0.characters) }.joined(separator: " | ") }
            }
        }
        return MarkdownBlocks.parse(markdown).flatMap(lines).joined(separator: "\n")
    }

    private func assertShownAsWritten(_ markdown: String, line: UInt = #line) {
        XCTAssertEqual(shown(markdown), markdown, line: line)
    }

    func testBackslashesInMathAreKept() {
        assertShownAsWritten(#"$S_n$ acts on $\{1, 2, \dots, n\}$."#)
        assertShownAsWritten(#"In $S_3$, $(1\,2)(2\,3) = (1\,2\,3)$ and $a\;b$."#)
        assertShownAsWritten(
            #"$$R = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}$$"#)
        assertShownAsWritten(#"\[ x = \frac{-b \pm \sqrt{b^2-4ac}}{2a} \]"#)
        assertShownAsWritten(#"Inline \( e^{-x^2} \) and \(\|\mathbf{x}\|\)."#)
        assertShownAsWritten(#"Rows \(\begin{pmatrix} a \\[4pt] b \end{pmatrix}\) spaced."#)
    }

    func testAsterisksInMathAreNotEmphasis() {
        assertShownAsWritten("Let $f*g$ be the convolution and $g*h$ another.")
        assertShownAsWritten(#"Write $\mathbb{R}^*$ and $G^*$ for duals."#)
    }

    func testMoneyIsNotMath() {
        XCTAssertEqual(
            shown("It never lands exactly on $0:\n\n- n = 4 → **$2.00** left\n- n = 5 → −$2.50"),
            "It never lands exactly on $0:\nn = 4 → $2.00 left\nn = 5 → −$2.50")
        assertShownAsWritten("$5 and $6, or $20 - 4.50n$.")
        XCTAssertEqual(shown(#"It costs \$4.50 a cup."#), "It costs $4.50 a cup.", "an escaped dollar in prose")
        assertShownAsWritten(#"Let \(C = \$4.50\) be the price."#)
    }

    /// The `$` before `a` cannot close `$5`, being after a space, and so
    /// `$5` is given up and the scan goes on from the `5`.
    func testAFailedCloseGivesUpOnlyThatDollar() {
        let blocks = MarkdownBlocks.parse("$5 and $a*b$ or $c*d$")
        guard case .paragraph(let text) = blocks.first else { return XCTFail("\(blocks)") }
        XCTAssertEqual(String(text.characters), "$5 and $a*b$ or $c*d$")
        XCTAssertFalse(text.runs.contains { $0.inlinePresentationIntent != nil })
    }

    func testMathKeepsTheStyleAroundIt() {
        let blocks = MarkdownBlocks.parse("**Elementary ($e_k$):** sums")
        guard case .paragraph(let text) = blocks.first else { return XCTFail("\(blocks)") }
        XCTAssertEqual(String(text.characters), "Elementary ($e_k$): sums")
        XCTAssertFalse(text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        let strong = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        XCTAssertEqual(strong.map { String(text[$0.range].characters) }, ["Elementary ($e_k$):"])
    }

    func testMathInEveryKindOfBlock() {
        XCTAssertEqual(shown(#"# The set $\{x\}$"#), #"The set $\{x\}$"#)
        XCTAssertEqual(shown(#"> quoted $a\,b$"#), #"quoted $a\,b$"#)
        XCTAssertEqual(shown("| a | b |\n|---|---|\n| $\\{x\\}$ | y |"), "a | b\n$\\{x\\}$ | y")
        XCTAssertEqual(
            shown("- bases\n  - $e_1 = x_1 + \\dots$\n  - $e_2 = x_1x_2 + \\dots$"),
            "bases\n- $e_1 = x_1 + \\dots$\n  - $e_2 = x_1x_2 + \\dots$")
    }

    func testABarInMathDoesNotSplitATableCell() {
        XCTAssertEqual(
            shown("| Name | Value |\n|---|---|\n| Order | \\(|S_n| = n!\\) |"),
            "Name | Value\nOrder | \\(|S_n| = n!\\)")
    }

    func testMathOverLinesReadsAsOneLine() {
        XCTAssertEqual(
            shown("- the form\n  \\[\n    \\mathbf{x}\\cdot\\mathbf{y} = x_1y_1 \\\\ + x_2y_2\n  \\]"),
            #"the form \[ \mathbf{x}\cdot\mathbf{y} = x_1y_1 \\ + x_2y_2 \]"#)
        XCTAssertEqual(shown("> $$x\n> = \\frac{1}{2}$$"), #"$$x = \frac{1}{2}$$"#)
        XCTAssertEqual(shown("Consider \\(I^2 = a\\,b\n  = c\\,d\\)."), #"Consider \(I^2 = a\,b = c\,d\)."#)
        XCTAssertEqual(
            shown("\\[\n\\left|\\sum_i x_i\\right|\n\\le 1\n\\]"), #"\[ \left|\sum_i x_i\right| \le 1 \]"#,
            "a bar outside a table")
    }

    /// A line inside the math that would end its paragraph leaves the math as
    /// markdown, as before, and nothing of the wrapping shows.
    func testALineThatWouldEndTheParagraphLeavesTheMathAlone() {
        for line in [
            "", "# h", "<div>", "```", "~~~", "> q", "- x", "+ x", "* x", "1. x", "2) x", "---", "===", "***", "|---|",
        ] {
            let text = shown("$$a\n\(line)\nb$$")
            XCTAssertFalse(text.contains(MathSpans.marker) || text.contains(MathSpans.pipe), line)
            XCTAssertFalse(text.contains("`"), line)
        }
        XCTAssertEqual(shown("$$a\n-\\sin b$$"), #"$$a -\sin b$$"#, "a minus is no bullet")
    }

    func testCodeIsLeftAlone() {
        XCTAssertEqual(shown("Run `echo $x$ \\{y\\}` now."), "Run echo $x$ \\{y\\} now.")
        XCTAssertEqual(shown("```\nprice = $5$ \\{x\\}\n```"), "price = $5$ \\{x\\}")
        XCTAssertEqual(shown("```tex\n\n$a\\,b$\n```"), "\n$a\\,b$", "a fence with a blank line")
        XCTAssertEqual(shown("    $a\\,b$ indented"), "$a\\,b$ indented")
    }

    func testEmphasisOutsideMathStillApplies() {
        let blocks = MarkdownBlocks.parse("*one* and $a*b$ and **two**")
        guard case .paragraph(let text) = blocks.first else { return XCTFail("\(blocks)") }
        XCTAssertEqual(String(text.characters), "one and $a*b$ and two")
        XCTAssertEqual(text.runs.filter { $0.inlinePresentationIntent != nil }.count, 2)
    }
}
