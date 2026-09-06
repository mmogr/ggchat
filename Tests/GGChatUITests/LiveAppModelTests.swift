import GGChatCore
import XCTest

@testable import GGChatUI

/// The first real end-to-end test: the app model against a running server,
/// with `GGCHAT_LIVE_BASE_URL` set. Skipped otherwise.
final class LiveAppModelTests: XCTestCase {
    @MainActor
    func testAddByURLListModelsStreamAndProbeStatus() async throws {
        guard let raw = ProcessInfo.processInfo.environment["GGCHAT_LIVE_BASE_URL"],
            let url = ProviderConfig.normalizedBaseURL(from: raw)
        else { throw XCTSkip("GGCHAT_LIVE_BASE_URL is not set") }
        let model = AppModel(store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink())
        let config = ProviderConfig(name: "live", kind: .openAICompatible(baseURL: url))
        let key = ProcessInfo.processInfo.environment["GGCHAT_LIVE_API_KEY"] ?? ""
        try model.addProvider(config, credentials: [.apiKey: key])
        await model.refreshModels(for: config)
        XCTAssertFalse(model.models(for: config.id).isEmpty)
        XCTAssertNotNil(model.providers.first?.defaultModel, "the first listed model becomes the default")

        model.newConversation()
        let task = try XCTUnwrap(model.send("Reply with the single word: ok"))
        await task.value
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.role, .assistant)
        XCTAssertFalse(messages.last?.content.isEmpty ?? true)
        XCTAssertEqual(messages.last?.isPartial, false)
        XCTAssertNil(model.streamError(for: try XCTUnwrap(model.selectedConversationID)))

        await model.probeProxyStatus(for: config)
        _ = model.proxyStatusAvailable(for: config.id)
    }
}
