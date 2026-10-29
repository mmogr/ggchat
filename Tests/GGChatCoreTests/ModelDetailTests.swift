import XCTest

@testable import GGChatCore

/// The one line under a model's name in the model list, read out of gglib's
/// description and any other server's.
final class ModelDetailTests: XCTestCase {
    /// gglib's recorded list says each model's size and quantization, and
    /// the line is those two and nothing of the architecture.
    func testGGLibsDescriptionReadsAsItsSizeAndQuantization() throws {
        let models = try JSONDecoder().decode(ModelsResponse.self, from: try Fixtures.data("gglib-models.json")).data
        XCTAssertEqual(
            models.map(\.detailLine), ["28B · Q8_0", "31B · Q8_0", "24B · Q8_0", "4B · Q8_0", "27B · Q8_0"])
        XCTAssertEqual(ModelInfo.detailLine(describing: "qwen35 - 4B parameters, Q6_K_XL"), "4B · Q6_K_XL")
        XCTAssertEqual(ModelInfo.detailLine(describing: "qwen3 - 0.6B parameters, Q4_K_M"), "0.6B · Q4_K_M")
    }

    /// A part gglib's catalogue does not know, which it writes as
    /// "unknown", is left out, and a description with neither part known
    /// has no line.
    func testAPartGGLibCallsUnknownIsLeftOut() {
        XCTAssertEqual(ModelInfo.detailLine(describing: "llama - 8B parameters, unknown"), "8B")
        XCTAssertEqual(ModelInfo.detailLine(describing: "unknown - unknown parameters, Q8_0"), "Q8_0")
        XCTAssertNil(ModelInfo.detailLine(describing: "unknown - unknown parameters, unknown"))
    }

    /// Any other server's description is shown as it came, on one line, and
    /// none, or one of nothing but space, has no line.
    func testAnotherDescriptionIsShownOnOneLine() {
        XCTAssertEqual(
            ModelInfo(id: "mock-4b", description: "a smaller canned model").detailLine, "a smaller canned model")
        XCTAssertEqual(ModelInfo.detailLine(describing: "  a model\n  for chat \r\n"), "a model for chat")
        XCTAssertNil(ModelInfo(id: "plain").detailLine)
        XCTAssertNil(ModelInfo.detailLine(describing: " \n "))
    }
}
