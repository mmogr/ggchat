import XCTest

@testable import GGChatCore

/// The Thinking switch on the wire, for a conversation kept on this device:
/// gglib's model list says which models think, and a request turns thinking
/// off with a budget of zero and says nothing of it otherwise.
final class ThinkingWireTests: XCTestCase {
    private let question = [
        Message(role: .system, content: "Be brief.", createdAt: .distantPast),
        Message(role: .user, content: "hi / there", createdAt: .distantPast),
    ]

    private func sortedJSON(_ request: ChatRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(ChatCompletionRequest(request)), as: UTF8.self)
    }

    /// gglib's model list says which model thinks with `reasoning`, beside
    /// `vision` and apart from it, and leaves `capabilities` out for a model
    /// with nothing to list. The fixture's `reasoning` row was written by
    /// hand from gglib's client guide (`docs/clients.md`, "Thinking"), as
    /// its `vision` row was from `capabilities_of`; it was not recorded.
    func testAModelThatThinksSaysSoInItsCapabilities() throws {
        let models = try JSONDecoder().decode(ModelsResponse.self, from: try Fixtures.data("gglib-models.json")).data
        let thinking = try XCTUnwrap(models.first { $0.id == "Gemma-4-31B-It" })
        XCTAssertEqual(thinking.capabilities, ["reasoning"])
        XCTAssertTrue(thinking.thinks)
        XCTAssertFalse(thinking.readsImages, "a model that thinks was taken for one that reads images")
        let seeing = try XCTUnwrap(models.first { $0.id == "Qwen3.8-27B" })
        XCTAssertFalse(seeing.thinks, "a model that reads images was taken for one that thinks")
        XCTAssertEqual(models.filter(\.thinks).map(\.id), ["Gemma-4-31B-It"])
        // An older gglib, and any other server, lists no capabilities.
        XCTAssertFalse(ModelInfo(id: "plain").thinks)
        XCTAssertFalse(ModelInfo(id: "none", capabilities: []).thinks)
        XCTAssertFalse(ModelInfo(id: "e", capabilities: ["embeddings", "Reasoning"]).thinks)
        let both = ModelInfo(id: "both", capabilities: ["vision", "reasoning"])
        XCTAssertTrue(both.thinks)
        XCTAssertTrue(both.readsImages)
    }

    /// Off is `reasoning_budget_tokens: 0` beside the keys that were there.
    /// With nothing said the body has no such key and is the bytes it was
    /// before the switch existed: the expected text is the one
    /// `ImageContentWireTests` took from the encoding before images.
    func testOffIsABudgetOfZeroAndOtherwiseTheBodyIsByteForByteWhatItWas() throws {
        let before =
            #"{"messages":[{"content":"Be brief.","role":"system"},{"content":"hi \/ there","role":"user"}],"#
            + #""model":"m","return_progress":true,"stream":true,"stream_options":{"include_usage":true}}"#
        let plain = ChatRequest(model: "m", messages: question, returnProgress: true)
        XCTAssertNil(plain.reasoningBudgetTokens)
        XCTAssertEqual(try sortedJSON(plain), before)

        XCTAssertEqual(ChatRequest.noThinking, 0)
        var off = plain
        off.reasoningBudgetTokens = ChatRequest.noThinking
        XCTAssertEqual(
            try sortedJSON(off),
            #"{"messages":[{"content":"Be brief.","role":"system"},{"content":"hi \/ there","role":"user"}],"#
                + #""model":"m","reasoning_budget_tokens":0,"return_progress":true,"stream":true,"#
                + #""stream_options":{"include_usage":true}}"#)

        // The app's own encoder, which sorts nothing: the same bytes with the
        // budget unsaid as with no such field, and no key under any name.
        let sent = try JSONEncoder().encode(ChatCompletionRequest(plain))
        XCTAssertFalse(String(decoding: sent, as: UTF8.self).contains("reasoning"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        XCTAssertEqual(object.keys.sorted(), ["messages", "model", "return_progress", "stream", "stream_options"])
        let offObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(off))) as? [String: Any])
        XCTAssertEqual(offObject["reasoning_budget_tokens"] as? Int, 0)
        XCTAssertEqual(offObject.count, object.count + 1)
    }
}
