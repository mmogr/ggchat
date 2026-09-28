import XCTest

@testable import GGChatUI

/// What the window is given to show when opening the store had something to
/// say: the words, their order, and which line can be closed.
final class StoreNoticeTests: XCTestCase {
    /// With both lines to show, the red one comes first. Each reads as written
    /// here, as does the label of the button that closes the second.
    @MainActor
    func testTheRedLineComesFirstAndEachLineReadsAsWritten() {
        let shown = ShownStoreNotice(StoreNotice(keptInMemory: true, olderStoreLeftBehind: true))

        XCTAssertEqual(
            shown.lines.map(\.sentence),
            [
                "ggchat could not open your saved conversations. They have not been deleted. "
                    + "Conversations and providers you add now will not be saved.",
                "An older version of ggchat was run on this device and kept saved conversations of its own, "
                    + "if it made any. They are not shown here. Nothing has been deleted.",
            ])
        XCTAssertEqual(StoreNotice.closeOlderStoreLine, "Hide this message for now")
    }

    /// Closing takes away the older store's line and never the red one.
    @MainActor
    func testClosingHidesTheOlderStoresLineAndNeverTheRedOne() {
        let both = ShownStoreNotice(StoreNotice(keptInMemory: true, olderStoreLeftBehind: true))
        let red = ShownStoreNotice(StoreNotice(keptInMemory: true, olderStoreLeftBehind: false))
        let older = ShownStoreNotice(StoreNotice(keptInMemory: false, olderStoreLeftBehind: true))
        XCTAssertEqual(older.lines, [.olderStore])

        for shown in [both, red, older] {
            shown.closeOlderStoreLine()
        }

        XCTAssertEqual(both.lines, [.keptInMemory])
        XCTAssertEqual(red.lines, [.keptInMemory])
        XCTAssertEqual(older.lines, [])
        XCTAssertEqual(ShownStoreNotice(nil).lines, [])
    }
}
