import XCTest

@testable import GGChatUI

/// Where the conversation list is kept beside the chat: on a regular-width
/// window taller than it is wide, and nowhere else.
final class SidebarPinningTests: XCTestCase {
    /// An iPhone Duo's inner display, open and held upright.
    private let open = CGSize(width: 669, height: 951)

    func testAnOpenDuoHeldUprightKeepsTheListBesideTheChat() {
        XCTAssertTrue(SidebarPinning.pins(regularWidth: true, size: open))
    }

    func testAWideWindowLeavesTheListToTheSystem() {
        XCTAssertFalse(SidebarPinning.pins(regularWidth: true, size: CGSize(width: 951, height: 669)))
    }

    func testAFoldedDuoIsAPhoneWithItsListAScreenBack() {
        XCTAssertFalse(SidebarPinning.pins(regularWidth: false, size: CGSize(width: 466, height: 678)))
    }

    func testAFoldedDuoOnItsSideLeavesTheListToTheSystem() {
        XCTAssertFalse(SidebarPinning.pins(regularWidth: false, size: CGSize(width: 678, height: 466)))
        XCTAssertFalse(SidebarPinning.pins(regularWidth: true, size: CGSize(width: 678, height: 466)))
    }

    func testASquareWindowLeavesTheListToTheSystem() {
        XCTAssertFalse(SidebarPinning.pins(regularWidth: true, size: CGSize(width: 800, height: 800)))
    }

    func testAWindowTooNarrowForTheListAndAChatLeavesTheListToTheSystem() {
        XCTAssertFalse(SidebarPinning.pins(regularWidth: true, size: CGSize(width: 599, height: 900)))
        XCTAssertTrue(SidebarPinning.pins(regularWidth: true, size: CGSize(width: 600, height: 900)))
    }
}
