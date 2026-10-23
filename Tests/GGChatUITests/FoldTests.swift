import XCTest

@testable import GGChatUI

/// Where a composer goes on a half-open phone: to the trailing side of a
/// vertical fold it would cross, and nowhere otherwise.
final class FoldTests: XCTestCase {
    /// A detail column on the open inner display with the sidebar hidden.
    private let row = CGSize(width: 903, height: 120)
    private let column: CGFloat = 760
    /// A vertical fold near the middle of that row.
    private let fold = CGRect(x: 440, y: -500, width: 24, height: 1000)

    func testWithNoFoldTheColumnStaysCentred() {
        XCTAssertEqual(Fold.leadingClearance(column: column, in: row, avoiding: []), 0)
    }

    func testAColumnAcrossAVerticalFoldStartsAtTheFoldsTrailingEdge() {
        XCTAssertEqual(Fold.leadingClearance(column: column, in: row, avoiding: [fold]), 464)
    }

    func testAFoldTheColumnDoesNotReachLeavesItWhereItIs() {
        let wide = CGSize(width: 1366, height: 120)
        let near = CGRect(x: 100, y: -500, width: 24, height: 1000)
        XCTAssertEqual(Fold.leadingClearance(column: column, in: wide, avoiding: [near]), 0)
    }

    func testAHorizontalFoldAsksNothingOfTheColumn() {
        let propped = CGRect(x: 0, y: 40, width: 903, height: 24)
        XCTAssertEqual(Fold.leadingClearance(column: column, in: row, avoiding: [propped]), 0)
    }

    func testAPaneTooNarrowToMoveIntoIsNotMovedInto() {
        let late = CGRect(x: 700, y: -500, width: 24, height: 1000)
        XCTAssertEqual(Fold.leadingClearance(column: column, in: row, avoiding: [late]), 0)
    }
}
