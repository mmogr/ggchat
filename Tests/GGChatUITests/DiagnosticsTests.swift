import XCTest

@testable import GGChatUI

final class DiagnosticsTests: XCTestCase {
    @MainActor
    func testDistinctTicketsSurviveARelaunch() {
        let suite = "DiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let diagnostics = Diagnostics(defaults: defaults)
        diagnostics.recordTicket(digest: "a")
        diagnostics.recordTicket(digest: "a")
        diagnostics.recordTicket(digest: "b")

        let reloaded = Diagnostics(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.ticketDigests, ["a", "b"])
    }
}
