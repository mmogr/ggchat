import XCTest

@testable import GGChatCore

final class WireTests: XCTestCase {
    private func chunks() throws -> [ChatCompletionChunk] {
        var parser = SSEParser()
        let items = parser.feed(try Fixtures.data("gglib-stream-reasoning.sse")) + parser.finish()
        return try items.compactMap { item -> ChatCompletionChunk? in
            guard case .event(let event) = item else { return nil }
            return try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(event.data.utf8))
        }
    }

    func testFirstChunkHasNoChoicesKeyAndStillDecodes() throws {
        let first = try XCTUnwrap(try chunks().first)
        XCTAssertNil(first.choices)
    }

    func testReasoningArrivesAsReasoningContent() throws {
        let reasoning = try chunks().compactMap { $0.choices?.first?.delta?.reasoningContent }
        XCTAssertGreaterThan(reasoning.count, 5)
        XCTAssertTrue(reasoning.allSatisfy { !$0.isEmpty })
    }

    func testUsageChunkHasEmptyChoicesAndCachedTokens() throws {
        let usage = try XCTUnwrap(try chunks().last(where: { $0.usage != nil }))
        XCTAssertEqual(usage.choices?.count, 0)
        XCTAssertEqual(usage.usage?.promptTokens, 57)
        XCTAssertEqual(usage.usage?.completionTokens, 28)
        XCTAssertEqual(usage.usage?.totalTokens, 85)
        XCTAssertEqual(usage.usage?.cachedTokens, 42)
    }

    func testFinishReasonStop() throws {
        let reasons = try chunks().compactMap { $0.choices?.first?.finishReason }
        XCTAssertEqual(reasons, ["stop"])
    }

    func testModelsFixtureCarriesGGLibExtras() throws {
        let models = try JSONDecoder().decode(ModelsResponse.self, from: try Fixtures.data("gglib-models.json")).data
        XCTAssertEqual(models.count, 5)
        XCTAssertEqual(models.first?.ownedBy, "gglib")
        XCTAssertNotNil(models.first?.contextWindow)
        XCTAssertNotNil(models.first?.description)
    }

    func testModelsWithoutExtrasDecode() throws {
        let json = #"{"object":"list","data":[{"id":"llama3","object":"model"}]}"#
        let models = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8)).data
        XCTAssertEqual(models, [ModelInfo(id: "llama3")])
    }

    func testProxyStatusFixture() throws {
        let status = try JSONDecoder().decode(ProxyStatus.self, from: try Fixtures.data("gglib-proxy-status.json"))
        XCTAssertEqual(status.activeConnectionCount, 0)
        XCTAssertEqual(status.slots.first?.contextSize, 131_072)
        XCTAssertNotNil(status.slots.first?.isProcessing)
        XCTAssertFalse(status.recentRequests.isEmpty)
        XCTAssertEqual(status.recentRequests.first?.modelName, "Qwen3.8-27B")
    }

    func testProxyStatusStreamFixtureFirstEventIsASnapshot() throws {
        var parser = SSEParser()
        let items = parser.feed(try Fixtures.data("gglib-proxy-status-stream.sse"))
        guard case .event(let event)? = items.first else { return XCTFail("no event") }
        XCTAssertNoThrow(try JSONDecoder().decode(ProxyStatus.self, from: Data(event.data.utf8)))
    }

    func testErrorBodyFromGGLib() throws {
        let body = try JSONDecoder().decode(
            APIErrorBody.self, from: try Fixtures.data("gglib-error-profile-not-found.json"))
        XCTAssertEqual(body.error.code, "profile_not_found")
        XCTAssertEqual(body.error.type, "invalid_request_error")
        XCTAssertTrue(body.error.message.contains("not an inference profile"))
    }

    func testNumericErrorCodeIsKeptAsText() throws {
        let body = try JSONDecoder().decode(
            APIErrorBody.self, from: Data(#"{"error":{"message":"m","code":400}}"#.utf8))
        XCTAssertEqual(body.error.code, "400")
        let nullCode = try JSONDecoder().decode(
            APIErrorBody.self, from: Data(#"{"error":{"message":"m","code":null}}"#.utf8))
        XCTAssertNil(nullCode.error.code)
    }

    func testRequestEncodesStreamOptionsAndSnakeCase() throws {
        let request = ChatRequest(
            model: "m", messages: [Message(role: .user, content: "hi", createdAt: .distantPast)], maxTokens: 5)
        let data = try JSONEncoder().encode(ChatCompletionRequest(request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual(object["max_tokens"] as? Int, 5)
        XCTAssertEqual((object["stream_options"] as? [String: Any])?["include_usage"] as? Bool, true)
        XCTAssertEqual((object["messages"] as? [[String: Any]])?.first?["role"] as? String, "user")
    }
}
