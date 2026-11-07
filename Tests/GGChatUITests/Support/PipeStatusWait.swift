import GGChatCore
import XCTest

@testable import GGChatUI

/// Waits for a pipe's status on a clock rather than on a count of yields.
///
/// A status arrives from a task on the global executor, and a loaded machine
/// can keep it waiting for a thread for longer than any count of yields: a
/// wait that gives up after so many turns lets the assertion after it fail on
/// a state that was still on its way. This polls for up to `limit`, for
/// `GatedConnector.waitForArrivals`'s reason, and fails at the caller as a
/// timeout when the status never arrives.
///
/// Its own name, not `waitForStatus`, which several suites declare privately,
/// some over an optional status.
@MainActor
enum PipeStatusWait {
    static func until(
        _ wanted: PipeStatus, _ model: AppModel, _ id: UUID, within limit: Duration = .seconds(10),
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let deadline = ContinuousClock.now + limit
        while model.pipeStatus(for: id) != wanted, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(
            model.pipeStatus(for: id), wanted, "the pipe never read \(wanted.rawValue)", file: file, line: line)
    }
}
