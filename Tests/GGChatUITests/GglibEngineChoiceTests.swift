import GGChatCore
import GGChatLocal
import XCTest

@testable import GGChatUI

/// Where gglib's engine is chosen: on the Mac, which these tests run on, no
/// engine runs.
@MainActor
final class GglibEngineChoiceTests: XCTestCase {
    /// The Mac gets no engine, gglib's or the mock's: nothing on-device is
    /// offered there.
    func testTheMacRunsNoEngine() {
        XCTAssertFalse(GglibEngine.runsHere)
        XCTAssertTrue(EngineFactory.makeEngine() is UnavailableEngine)
    }
}
