import GGChatCore
import XCTest

@testable import GGChatUI

/// Math in a reply is drawn by SwiftMath, after the few commands it lacks
/// are said in ones it has.
final class MathTextTests: XCTestCase {
    /// A reply Qwen gave about partial orders, which showed every span as
    /// LaTeX until `\mathrel` was said another way.
    private let partialOrders = #"""
        A relation $R$ on a set $S$ is a **partial order** if it is:

        1. **Reflexive** — $\forall a \in S,\ a \mathrel{R} a$ (every element is related to itself)
        2. **Antisymmetric** — $\forall a, b \in S,\ (a \mathrel{R} b \land b \mathrel{R} a) \implies a = b$
        3. **Transitive** — $\forall a, b, c \in S,\ (a \mathrel{R} b \land b \mathrel{R} c) \implies a \mathrel{R} c$

        If every two elements are comparable (for all $a, b$:
        $a \mathrel{R} b$ or $b \mathrel{R} a$), it is a **total order**.
        """#

    private func spans(_ blocks: [MarkdownBlock]) -> [MathSpan] {
        blocks.flatMap { block -> [AttributedString] in
            switch block {
            case .paragraph(let text), .heading(_, let text): [text]
            case .list(_, let items): items
            default: []
            }
        }
        .flatMap { $0.runs.compactMap { $0[MathAttribute.self] } }
    }

    @MainActor
    func testEverySpanOfAPartialOrderReplyIsDrawn() {
        let spans = spans(MarkdownBlocks.parse(partialOrders))
        XCTAssertEqual(spans.count, 8)
        for span in spans {
            XCTAssertTrue(MathImages.canDraw(span), span.latex)
        }
    }

    @MainActor
    func testCommandsSwiftMathLacksAreDrawn() {
        for latex in [#"\{1, \dots, n\}"#, #"\lvert x \rvert"#, #"\lVert v \rVert"#, #"a\:b"#, #"\operatorname{sgn}"#] {
            XCTAssertTrue(MathImages.canDraw(MathSpan(latex: latex, isDisplay: false)), latex)
        }
        let matrix = #"\begin{pmatrix} \cos\theta & -\sin\theta \\[4pt] \sin\theta & \cos\theta \end{pmatrix}"#
        XCTAssertTrue(MathImages.canDraw(MathSpan(latex: matrix, isDisplay: true)))
    }

    /// Shown as written instead, by the view, as it was before math was drawn.
    @MainActor
    func testMathSwiftMathCannotReadIsNotDrawn() {
        XCTAssertFalse(MathImages.canDraw(MathSpan(latex: #"\left( a \middle| b \right)"#, isDisplay: false)))
        XCTAssertFalse(MathImages.canDraw(MathSpan(latex: #"\frac{1}{"#, isDisplay: false)))
    }

    @MainActor
    func testShortMathKeepsItsBaselineInsideThePicture() {
        // `\ldots` is shorter than half the font size, which `MathImage`
        // would draw below its own bottom edge.
        XCTAssertNotNil(MathImages.text(for: MathSpan(latex: #"\ldots"#, isDisplay: false), size: 17))
        XCTAssertNotNil(MathImages.text(for: MathSpan(latex: "-", isDisplay: false), size: 17))
    }
}
