import GGChatCore
import XCTest

@testable import GGChatUI

final class DiagnosticsTests: XCTestCase {
    @MainActor
    func testReadingsPersistWithTheirDenominators() {
        let suite = "DiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let diagnostics = Diagnostics(defaults: defaults)
        diagnostics.recordResume(at: stamp)
        diagnostics.recordStreamEnd(with: .transport("gone"), at: stamp.addingTimeInterval(2))
        diagnostics.recordStreamEnd(with: .transport("gone"), at: stamp.addingTimeInterval(9), )
        diagnostics.recordStreamEnd(
            with: .server(status: 400, code: "bad_request", message: "m"), at: stamp.addingTimeInterval(1))
        diagnostics.recordClosed(whileStreaming: true)
        diagnostics.recordClosed(whileStreaming: false)
        diagnostics.recordContinue()
        diagnostics.recordTicket(digest: "a")
        diagnostics.recordTicket(digest: "a")
        diagnostics.recordTicket(digest: "b")

        let reloaded = Diagnostics(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.foregroundResumes, 1)
        XCTAssertEqual(reloaded.transportErrorsAfterResume, 1, "only the transport error within five seconds counts")
        XCTAssertEqual(reloaded.closedTransitions, 2)
        XCTAssertEqual(reloaded.closedWhileStreaming, 1)
        XCTAssertEqual(reloaded.continuePresses, 1)
        XCTAssertEqual(reloaded.ticketDigests, ["a", "b"])
    }
}
