import GGChatCore
import XCTest

@testable import GGChatUI

/// Which of a provider's models a conversation is offered, once gglib lists
/// models that draw pictures beside the ones that chat.
final class DrawingModelListTests: XCTestCase {
    static let listed = [
        ModelInfo(id: "flux-dev", capabilities: ["image_generation"]),
        ModelInfo(id: "bge-small", capabilities: ["embeddings"]),
        ModelInfo(id: "qwen3-vl", capabilities: ["vision", "reasoning"]),
        ModelInfo(id: "plain"),
    ]

    /// A model on a server that lists `listed`, added with no model chosen.
    @MainActor
    private func makeModel() throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "DrawingModelListTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults))
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49981/v1"))
        registry.register(MockProvider(models: Self.listed), at: url)
        let config = ProviderConfig(name: "home", kind: .openAICompatible(baseURL: url))
        try model.addProvider(config, credentials: [:])
        return (model, config)
    }

    /// The model list offers the models that chat, in the order listed. One
    /// that draws and one that serves embeddings are left out of it, and are
    /// still among the provider's models.
    @MainActor
    func testTheModelListOffersOnlyModelsThatCanChat() async throws {
        let (model, config) = try makeModel()
        await model.refreshModels(for: config)
        XCTAssertEqual(model.models(for: config.id).map(\.id), ["flux-dev", "bge-small", "qwen3-vl", "plain"])
        XCTAssertEqual(model.chatModels(for: config.id).map(\.id), ["qwen3-vl", "plain"])
    }

    /// A provider with no model chosen takes the first that can chat, not
    /// the first listed, which here draws.
    @MainActor
    func testTheDefaultModelIsTheFirstThatCanChat() async throws {
        let (model, config) = try makeModel()
        await model.refreshModels(for: config)
        XCTAssertEqual(model.providers.first?.defaultModel, "qwen3-vl")
        XCTAssertEqual(model.newConversation().model, "qwen3-vl")
    }
}
