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

    /// gglib puts the context's size and the count of messages trimmed to
    /// fit inside `usage`, for a request that asked for progress. The frame
    /// is the recorded usage frame with the two keys added by hand, pending
    /// gglib's own recording. The recorded stream, from before them, reads
    /// as it did, with neither.
    func testUsageReadsGglibsTwoKeysAndReadsWithoutThem() throws {
        let frame =
            #"{"choices":[],"usage":{"completion_tokens":28,"prompt_tokens":57,"prompt_tokens_details":"#
            + #"{"cached_tokens":42},"total_tokens":85,"context_size":8192,"trimmed_messages":2}}"#
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(frame.utf8))
        let recorded = Usage(promptTokens: 57, completionTokens: 28, totalTokens: 85, cachedTokens: 42)
        var want = recorded
        want.contextSize = 8_192
        want.trimmedMessages = 2
        XCTAssertEqual(chunk.usage, want)
        XCTAssertEqual(try chunks().last(where: { $0.usage != nil })?.usage, recorded)
        XCTAssertNil(recorded.contextSize)
        XCTAssertNil(recorded.trimmedMessages)

        let encoded = try JSONEncoder().encode(Usage(contextSize: 8_192, trimmedMessages: 2))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Int])
        XCTAssertEqual(object, ["context_size": 8_192, "trimmed_messages": 2])
        XCTAssertEqual(try JSONDecoder().decode(Usage.self, from: try JSONEncoder().encode(want)), want)
    }

    /// Either of gglib's two keys that does not read is dropped, and the
    /// counts and the other key are read as before: a frame that decoded
    /// without them still does.
    func testAContextKeyThatDoesNotReadCostsOnlyItself() throws {
        func usage(_ extras: String) throws -> Usage? {
            let frame = #"{"choices":[],"usage":{"completion_tokens":28,"prompt_tokens":57,\#(extras)}}"#
            return try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(frame.utf8)).usage
        }
        let counts = Usage(promptTokens: 57, completionTokens: 28)
        for size in [#""8192""#, "81.5", "null", "{}", "true"] {
            var want = counts
            want.trimmedMessages = 2
            XCTAssertEqual(try usage(#""context_size":\#(size),"trimmed_messages":2"#), want, size)
        }
        for trimmed in [#""two""#, "2.5", "null", "[2]"] {
            var want = counts
            want.contextSize = 8_192
            XCTAssertEqual(try usage(#""context_size":8192,"trimmed_messages":\#(trimmed)"#), want, trimmed)
        }
        XCTAssertEqual(try usage(#""context_size":[],"trimmed_messages":{}"#), counts)
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

    /// The frame gglib writes into a stream decodes as a chunk with an error
    /// and no choices, whether its code is text or a number and whether the
    /// error is an object or a bare string. An ordinary chunk has no error.
    func testABareErrorFrameDecodesAsAnErrorAndNoChoices() throws {
        let decode = { (json: String) in try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8)) }
        let bare = try decode(#"{"error":{"code":"upstream_error","message":"gone","type":"server_error"}}"#)
        XCTAssertNil(bare.choices)
        XCTAssertEqual(bare.error, .init(message: "gone", code: "upstream_error"))
        XCTAssertEqual(try decode(#"{"error":{"message":"busy","code":503}}"#).error?.code, "503")
        XCTAssertEqual(try decode(#"{"error":"model crashed"}"#).error, .init(message: "model crashed", code: nil))
        XCTAssertNil(try XCTUnwrap(try chunks().last).error)
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

    /// A conversation's prompt goes out as an ordinary turn with the role
    /// `system`, first, and with nothing on it but its role and its text.
    func testASystemMessageIsSentWithTheSystemRole() throws {
        let conversation = Conversation(
            messages: [Message(role: .user, content: "hi", createdAt: .distantPast)],
            systemPrompt: "Answer in French.", createdAt: .distantPast, updatedAt: .distantPast)
        let request = ChatRequest(model: "m", messages: conversation.requestMessages)
        let data = try JSONEncoder().encode(ChatCompletionRequest(request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(messages.first?["content"] as? String, "Answer in French.")
        XCTAssertEqual(messages.first?.keys.sorted(), ["content", "role"], "the turn's id and date stay on this side")
    }
}

final class ProxyStatusHelperTests: XCTestCase {
    func testContextUsageIsAFractionOrNil() throws {
        let status = try JSONDecoder().decode(ProxyStatus.self, from: try Fixtures.data("gglib-proxy-status.json"))
        let slot = try XCTUnwrap(status.slots.first)
        let usage = try XCTUnwrap(slot.contextUsage)
        XCTAssertEqual(usage, Double(slot.promptTokens!) / Double(slot.contextSize!), accuracy: 0.0001)
        let empty = try JSONDecoder().decode(ProxyStatus.self, from: Data(#"{"slots":[{"id":0}]}"#.utf8))
        XCTAssertNil(empty.slots.first?.contextUsage)
    }

    func testRecentRequestFlags() throws {
        let json =
            #"{"recent_requests":[{"model_name":"m","loop_guard_tripped":true,"messages_truncated":2},"#
            + #"{"model_name":"n"}]}"#
        let status = try JSONDecoder().decode(ProxyStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.recentRequests[0].flags, ["loop guard", "2 truncated"])
        XCTAssertEqual(status.recentRequests[1].flags, [])
    }

    /// gglib names the detector that tripped in `loop_guard_trip`, `null` for
    /// none; a hub from before that sent the Bool `loop_guard_tripped`, and
    /// both are read. The fixtures are the two shapes as each hub sends them.
    func testTheLoopGuardIsReadUnderTheKeyGGLibSendsAndTheOldOne() throws {
        let decode = { (json: String) in try JSONDecoder().decode(ProxyStatus.self, from: Data(json.utf8)) }
        let requests = try decode(
            #"{"recent_requests":[{"loop_guard_trip":"loop"},{"loop_guard_trip":"stagnation"},"#
                + #"{"loop_guard_trip":"a_detector_from_later"},{"loop_guard_trip":null},"#
                + #"{"loop_guard_tripped":true},{"loop_guard_tripped":false},{}]}"#
        ).recentRequests
        XCTAssertEqual(requests.map(\.loopGuardTripped), [true, true, true, false, true, false, nil])

        let now = try JSONDecoder().decode(ProxyStatus.self, from: try Fixtures.data("gglib-proxy-status.json"))
        let flagged = now.recentRequests.map { $0.flags.contains("loop guard") }
        XCTAssertEqual(flagged, [false, false, false, false, false, true])
        let before = try JSONDecoder().decode(
            ProxyStatus.self, from: try Fixtures.data("gglib-proxy-status-loop-guard-tripped.json"))
        XCTAssertEqual(before.recentRequests.map(\.loopGuardTripped), Array(repeating: false, count: 6))
    }
}
