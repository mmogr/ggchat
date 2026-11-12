import Foundation
import XCTest

@testable import GGChatCore

/// What a gglib says of itself beside its model list: read when it is there,
/// with the words this build does not know kept and meaning nothing, and
/// none from a server that says nothing or says it in a shape that does not
/// read, which never costs the list.
final class GGLibServerWireTests: XCTestCase {
    private func decode(_ json: String) throws -> ModelsResponse {
        try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
    }

    func testAGGLibSaysItsVersionAndWhatItServes() throws {
        let answer = try decode(
            #"{"object":"list","data":[{"id":"llama3"}],"machine_name":"desk","#
                + #""gglib":{"version":"0.35.0","features":["chats","runs","drawing","status"]}}"#)
        XCTAssertEqual(answer.data, [ModelInfo(id: "llama3")])
        XCTAssertEqual(answer.gglib, .serving("0.35.0"))
        for feature in GGLibFeature.allCases {
            XCTAssertTrue(answer.gglib?.serves(feature) == true, "\(feature)")
        }
    }

    /// A field and a feature word this build does not know mean nothing,
    /// and a feature not listed is not served.
    func testUnknownFieldsAndWordsMeanNothing() throws {
        let answer = try decode(
            #"{"data":[],"gglib":{"version":"0.37.0","features":["runs","telepathy"],"build":{"sha":"abc"}}}"#)
        XCTAssertEqual(answer.gglib?.version, "0.37.0")
        XCTAssertEqual(answer.gglib?.serves(.runs), true)
        XCTAssertEqual(answer.gglib?.serves(.chats), false)
        XCTAssertEqual(answer.gglib?.serves(.drawing), false)
        XCTAssertEqual(answer.gglib?.features, ["runs", "telepathy"])
    }

    /// A server that is not gglib, and a gglib from before 0.35.0, say nothing.
    func testAServerThatSaysNothingIsNoGGLib() throws {
        XCTAssertNil(try decode(#"{"object":"list","data":[{"id":"llama3"}],"machine_name":"desk"}"#).gglib)
    }

    /// One that does not read is none, and the list still reads.
    func testAGGLibObjectThatDoesNotReadCostsNothingElse() throws {
        for gglib in [#""0.35.0""#, #"{"version":36}"#, #"{"version":"0.35.0"}"#, #"{"features":["runs"]}"#, "null"] {
            let answer = try decode(#"{"data":[{"id":"llama3"}],"gglib":\#(gglib)}"#)
            XCTAssertNil(answer.gglib, gglib)
            XCTAssertEqual(answer.data, [ModelInfo(id: "llama3")], gglib)
        }
    }
}
