import XCTest

@testable import GGChatCore

/// Runs only with `GGCHAT_LIVE_BASE_URL` set, e.g. `http://127.0.0.1:8080/v1`
/// with gglib running. Skipped otherwise, so `swift test` stays hermetic.
final class LiveGGLibTests: XCTestCase {
    private func liveProvider() throws -> OpenAICompatibleProvider {
        guard let raw = ProcessInfo.processInfo.environment["GGCHAT_LIVE_BASE_URL"], let url = URL(string: raw) else {
            throw XCTSkip("GGCHAT_LIVE_BASE_URL is not set")
        }
        // A pipe requires its bearer token; a loopback gglib requires nothing.
        let key = ProcessInfo.processInfo.environment["GGCHAT_LIVE_API_KEY"]
        return OpenAICompatibleProvider(baseURL: url, apiKey: key)
    }

    func testLiveModelsAndAShortStream() async throws {
        let provider = try liveProvider()
        let models = try await provider.models()
        let model = try XCTUnwrap(models.first?.id)
        var events: [ChatEvent] = []
        let request = ChatRequest(
            model: model,
            messages: [Message(role: .user, content: "Reply with the single word: ok", createdAt: .distantPast)],
            maxTokens: 64)
        for await event in provider.stream(request) { events.append(event) }
        guard case .finished? = events.last else {
            return XCTFail("stream ended with \(String(describing: events.last))")
        }
        XCTAssertTrue(events.contains { if case .delta = $0 { true } else { false } })
    }

    func testLiveProxyStatusAnswersOrIsAbsent() async throws {
        let provider = try liveProvider()
        _ = try await provider.proxyStatus()
    }
}
