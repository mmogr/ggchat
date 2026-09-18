import XCTest

@testable import GGChatPipe

/// What `mpPair` hands back, as this app holds it, printed whole.
final class PairedDescriptionTests: XCTestCase {
    /// Interpolated, reflected or dumped, the key stays out and the device
    /// stays in, so the test cannot pass on an empty description.
    func testPairedPrintsItsDeviceAndNeverItsKey() {
        let key = "sk-this-key-must-never-print"
        let paired = ModelpipeConnector.Paired(pipe: FakePipe(), apiKey: key, device: "phone-1")
        var dumped = ""
        dump(paired, to: &dumped)
        let renderings = ["interpolated": "\(paired)", "reflected": String(reflecting: paired), "dumped": dumped]
        XCTAssertEqual("\(paired)", "Paired(device: phone-1, apiKey: <redacted>)")
        for (how, text) in renderings {
            XCTAssertFalse(text.contains(key), "\(how) printed the key: \(text)")
            XCTAssertTrue(text.contains("<redacted>"), "\(how): \(text)")
            XCTAssertTrue(text.contains("phone-1"), "\(how): \(text)")
        }
    }
}
