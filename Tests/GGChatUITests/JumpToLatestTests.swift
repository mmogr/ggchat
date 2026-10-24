import XCTest

@testable import GGChatUI

/// When a transcript offers its way back to the latest message: once it is
/// scrolled more than half a screen up, and never for a chat shorter than
/// its screen. The numbers are an iPhone 17 Pro's with the keyboard up, as
/// SwiftUI reported them: a frame 874 points tall, 116 of it under the bars
/// and 498 under the composer and keyboard, over 1,330 points of chat.
final class JumpToLatestTests: XCTestCase {
    private let frame: CGFloat = 874
    private let top: CGFloat = 116
    private let bottom: CGFloat = 498
    private let content: CGFloat = 1_330
    /// What can be read between the bars and the composer.
    private var viewport: CGFloat { frame - top - bottom }
    /// The visible rect's foot SwiftUI reported with the chat at its latest.
    private let atLatest: CGFloat = 1_828

    private func shows(visibleMaxY: CGFloat, content: CGFloat? = nil) -> Bool {
        let distance = JumpToLatest.distanceFromBottom(
            contentHeight: content ?? self.content, visibleMaxY: visibleMaxY, bottomInset: bottom)
        return JumpToLatest.shows(distanceFromBottom: distance, viewport: viewport)
    }

    func testAtTheBottomThereIsNoButton() {
        XCTAssertFalse(shows(visibleMaxY: atLatest))
    }

    func testTheComposersInsetIsNotCountedAsDistance() {
        XCTAssertEqual(
            JumpToLatest.distanceFromBottom(contentHeight: content, visibleMaxY: atLatest, bottomInset: bottom), 0)
    }

    func testScrolledUpLessThanHalfAScreenThereIsNoButton() {
        XCTAssertFalse(shows(visibleMaxY: atLatest - viewport / 2))
    }

    func testScrolledUpMoreThanHalfAScreenThereIsOne() {
        XCTAssertTrue(shows(visibleMaxY: atLatest - viewport / 2 - 1))
        // At the top, where the offset is the bars' height above zero.
        XCTAssertTrue(shows(visibleMaxY: frame - top))
    }

    func testAChatShorterThanItsScreenNeverHasOne() {
        XCTAssertFalse(shows(visibleMaxY: frame - top, content: 200))
    }

    func testAChatAtItsLatestIsKeptThereWhenTheKeyboardComesUp() {
        XCTAssertTrue(
            JumpToLatest.keepsToLatest(
                distanceBefore: 0, viewportBefore: viewport, insetBefore: 160, insetAfter: bottom))
    }

    func testAChatScrolledUpStaysWhereItIsWhenTheKeyboardComesUpOrGoes() {
        XCTAssertFalse(
            JumpToLatest.keepsToLatest(
                distanceBefore: viewport, viewportBefore: viewport, insetBefore: 160, insetAfter: bottom))
        XCTAssertFalse(
            JumpToLatest.keepsToLatest(
                distanceBefore: 0, viewportBefore: viewport, insetBefore: bottom, insetAfter: 160))
    }

    func testAChatAFewPointsShortOfItsLatestIsStillTakenThere() {
        // A finished reply's row drawn again a little taller, and the
        // keyboard back before the chat settled at its very bottom.
        XCTAssertTrue(
            JumpToLatest.keepsToLatest(
                distanceBefore: 12, viewportBefore: viewport, insetBefore: 160, insetAfter: bottom))
    }
}
