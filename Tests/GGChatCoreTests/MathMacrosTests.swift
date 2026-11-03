import XCTest

@testable import GGChatCore

/// The commands models write that SwiftMath does not know, said in ones it
/// does before drawing.
final class MathMacrosTests: XCTestCase {
    func testARelationIsItsSymbolWithThickSpaceAround() {
        XCTAssertEqual(
            MathMacros.expand(#"\forall a, b \in S,\ (a \mathrel{R} b \land b \mathrel{R} a) \implies a = b"#),
            #"\forall a, b \in S,\ (a \;R\; b \land b \;R\; a) \implies a = b"#)
        XCTAssertEqual(MathMacros.expand(#"a \mathrel {\overset{?}{=}} b"#), #"a \;\overset{?}{=}\; b"#)
        XCTAssertEqual(MathMacros.expand(#"\mathrel{\mathrel{R}}"#), #"\;\;R\;\;"#, "nested")
        XCTAssertEqual(MathMacros.expand(#"\mathrel{\{}"#), #"\;\{\;"#, "an escaped brace inside")
    }

    func testARelationWithoutABracedArgumentIsLeftAlone() {
        XCTAssertEqual(MathMacros.expand(#"a \mathrel= b"#), #"a \mathrel= b"#)
        XCTAssertEqual(MathMacros.expand(#"a \mathrel{R b"#), #"a \mathrel{R b"#)
    }

    func testOtherCommandsAreSaidInOnesSwiftMathKnows() {
        XCTAssertEqual(MathMacros.expand(#"1, 2, \dots, n"#), #"1, 2, \ldots, n"#)
        XCTAssertEqual(MathMacros.expand(#"\lvert x \rvert + \lVert v \rVert"#), #"\vert x \vert + \Vert v \Vert"#)
        XCTAssertEqual(MathMacros.expand(#"a\:b"#), #"a\>b"#)
    }

    func testLongerCommandsAndEscapedBackslashesAreLeftAlone() {
        XCTAssertEqual(MathMacros.expand(#"\dotsc \dotsb \lverta"#), #"\dotsc \dotsb \lverta"#)
        XCTAssertEqual(MathMacros.expand(#"a \\: b"#), #"a \\: b"#, "a line break, then a colon")
        XCTAssertEqual(MathMacros.expand(#"x^2 + y^2"#), #"x^2 + y^2"#)
        XCTAssertEqual(MathMacros.expand(#"ends in \"#), #"ends in \"#)
    }
}
