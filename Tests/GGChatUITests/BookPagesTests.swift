import CoreGraphics
import XCTest

@testable import GGChatUI

/// Where an open iPhone Duo on its side is laid out as two pages, and what
/// the chat's panel on the leading one holds.
final class BookPagesTests: XCTestCase {
    /// An iPhone Duo's inner display, open and on its side.
    private let open = CGSize(width: 951, height: 669)
    /// Its fold while half open, down the middle.
    private let fold = CGRect(x: 463, y: 0, width: 24, height: 669)

    func testAnOpenDuoOnItsSideIsReadAsSideways() {
        XCTAssertTrue(BookPages.opensSideways(open))
    }

    func testAFoldedDuoOnItsSideAndAProMaxTurnedAreNot() {
        XCTAssertFalse(BookPages.opensSideways(CGSize(width: 678, height: 466)))
        XCTAssertFalse(BookPages.opensSideways(CGSize(width: 956, height: 440)))
    }

    func testAnOpenDuoUprightIsNot() {
        XCTAssertFalse(BookPages.opensSideways(CGSize(width: 669, height: 951)))
    }

    func testTheWalkWaivesTheHeightButNotTheRoomForTwoPages() {
        XCTAssertTrue(BookPages.opensSideways(CGSize(width: 874, height: 402), anyHeight: true))
        XCTAssertFalse(BookPages.opensSideways(CGSize(width: 600, height: 300), anyHeight: true))
    }

    func testHalfOpenThePagesMeetAtTheFold() {
        let pages = BookPages.pages(in: open, folds: [fold])
        XCTAssertEqual(pages?.leading, 463)
        XCTAssertEqual(pages?.gap, 24)
    }

    func testFlatThereAreNoPages() {
        XCTAssertNil(BookPages.pages(in: open, folds: []))
    }

    func testAPropFoldAcrossTheScreenMakesNoPages() {
        let propped = CGRect(x: 0, y: 463, width: 669, height: 24)
        XCTAssertNil(BookPages.pages(in: CGSize(width: 669, height: 951), folds: [propped]))
    }

    func testAFoldLeavingAPageTooNarrowMakesNoPages() {
        let near = CGRect(x: 700, y: 0, width: 24, height: 669)
        XCTAssertNil(BookPages.pages(in: open, folds: [near]))
    }

    func testAListShownByHandWhileFlatGetsHalfTheScreen() {
        let pages = BookPages.even(in: open)
        XCTAssertEqual(pages.leading, 476)
        XCTAssertEqual(pages.gap, 0)
    }

    func testAChatKeptHereShowsEverythingItIsOffered() {
        let parts = ThisChatPart.parts(
            isMacsChat: false, thinks: true, offersTools: true, hasContext: true, reportsStatus: true
        )
        XCTAssertEqual(parts, [.model, .thinking, .tools, .systemPrompt, .context, .server])
    }

    func testAChatOfferedNothingStillShowsItsModelAndPrompt() {
        let parts = ThisChatPart.parts(
            isMacsChat: false, thinks: false, offersTools: false, hasContext: false, reportsStatus: false
        )
        XCTAssertEqual(parts, [.model, .systemPrompt])
    }

    func testAMacsChatHasNoToolsOrPromptHere() {
        let parts = ThisChatPart.parts(
            isMacsChat: true, thinks: true, offersTools: true, hasContext: true, reportsStatus: true
        )
        XCTAssertEqual(parts, [.model, .thinking, .context, .server])
    }
}
