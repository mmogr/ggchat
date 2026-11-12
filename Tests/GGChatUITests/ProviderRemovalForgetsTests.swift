import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A server whose model list is held until the test lets it go.
private final class HeldModels: Provider {
    private let state = Mutex((asked: 0, held: true))

    var asked: Int { state.withLock(\.asked) }

    func release() {
        state.withLock { $0.held = false }
    }

    func models() async throws -> [ModelInfo] {
        state.withLock { $0.asked += 1 }
        while state.withLock(\.held) { await Task.yield() }
        return MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { $0.finish() }
    }
}

/// Removing a provider leaves nothing kept under its id, and an answer it was
/// waiting for finds nothing to write into when it comes. Moving one to
/// another machine forgets the models the old one listed.
@MainActor
final class ProviderRemovalForgetsTests: XCTestCase {
    private let serverURL = URL(string: "http://127.0.0.1:49981/v1")!

    private func makeModel(serving provider: any Provider) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: serverURL)
        let defaults = UserDefaults(suiteName: "ProviderRemovalForgetsTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let server = ProviderConfig(name: "server", kind: .openAICompatible(baseURL: serverURL))
        try model.addProvider(server, credentials: [:])
        return (model, server)
    }

    /// What the model keeps under a provider's id, beyond its pipe, its Mac's
    /// chats and when it was heard, which their own tests read.
    private func kept(_ model: AppModel, _ id: UUID) -> [String] {
        var kept: [String] = []
        if model.modelsByProvider[id] != nil { kept.append("models") }
        if model.gglibAnswers[id] != nil { kept.append("its gglib") }
        if model.modelListing[id] != nil { kept.append("a list on its way") }
        if model.followed.contains(id) { kept.append("followed") }
        if model.opening[id] != nil { kept.append("opening") }
        if model.dialGeneration[id] != nil { kept.append("dial generation") }
        return kept
    }

    func testRemovingAProviderLeavesNothingKeptUnderItsID() async throws {
        let (model, server) = try makeModel(serving: MockProvider(gglib: .serving("0.35.0")))
        await model.open(server).value
        XCTAssertEqual(kept(model, server.id), ["models", "its gglib", "followed"])

        model.removeProvider(server.id)
        for _ in 0..<5_000 where !kept(model, server.id).isEmpty { await Task.yield() }

        XCTAssertEqual(kept(model, server.id), [], "the removed provider is still kept")
    }

    /// A conversation opening on the provider is called off with it, and the
    /// list it was asking for is not kept when it comes back.
    func testAModelListThatComesBackAfterItsProviderWasRemovedIsNotKept() async throws {
        let held = HeldModels()
        let (model, server) = try makeModel(serving: held)
        let opening = model.open(server)
        for _ in 0..<5_000 where held.asked == 0 { await Task.yield() }
        XCTAssertEqual(held.asked, 1, "the list was never asked for")

        model.removeProvider(server.id)
        XCTAssertNil(model.opening[server.id], "the opening was not called off")
        held.release()
        await opening.value

        XCTAssertNil(model.modelsByProvider[server.id], "a list for a removed provider was kept")
        XCTAssertNil(model.lastError)
    }

    /// A server moved to another address forgets the models the old one
    /// listed, and a list the old one sends back late is not kept for the
    /// new one. Kept, the default model it picks would also write the old
    /// address back over the move. The model each of its conversations
    /// chose, and its default, go too, even when the edit carries the old
    /// default: a gglib model's id names a model on the old machine alone.
    /// An edit that does not move it keeps them, and so does a move of a
    /// server whose list named its models by name.
    func testMovingAProviderForgetsTheModelsTheOldMachineListed() async throws {
        let held = HeldModels()
        let (model, server) = try makeModel(serving: held)
        var named = server
        named.defaultModel = "7"
        model.updateProvider(named)
        model.newConversation()
        let id = try XCTUnwrap(model.selectedConversationID)
        model.select(model: "7:creative", for: id)
        named.name = "desk"
        model.updateProvider(named)
        XCTAssertEqual(model.providers.first?.defaultModel, "7", "a rename forgot the default")
        XCTAssertEqual(model.selectedConversation?.model, "7:creative", "a rename forgot the chat's model")
        model.modelsByProvider[server.id] = [ModelInfo(id: "old-model", gglibID: 7)]
        let listing = Task { await model.refreshModels(for: server, quietly: true) }
        for _ in 0..<5_000 where held.asked == 0 { await Task.yield() }
        XCTAssertEqual(held.asked, 1, "the list was never asked for")

        var moved = named
        moved.kind = .openAICompatible(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:49980/v1")))
        model.updateProvider(moved)
        XCTAssertNil(model.modelsByProvider[server.id], "the old machine's models were kept after the move")
        XCTAssertNil(model.providers.first?.defaultModel, "the old machine's default was kept")
        XCTAssertNil(model.selectedConversation?.model, "the chat kept the old machine's model")
        held.release()
        await listing.value

        XCTAssertNil(model.modelsByProvider[server.id], "the old machine's late list was kept for the new one")
        XCTAssertEqual(model.providers.map(\.kind), [moved.kind], "the late list undid the move")

        var plain = try XCTUnwrap(model.providers.first)
        plain.defaultModel = "old-model"
        model.updateProvider(plain)
        model.select(model: "old-model", for: id)
        model.modelsByProvider[server.id] = [ModelInfo(id: "old-model")]
        plain.kind = .openAICompatible(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:49981/v1")))
        model.updateProvider(plain)
        XCTAssertEqual(model.providers.first?.defaultModel, "old-model", "a default named by its name was forgotten")
        XCTAssertEqual(model.selectedConversation?.model, "old-model", "a model named by its name was forgotten")
    }

    /// A list on its way from the old address is not waited for by one for
    /// the new: the move lets it go, the new address is asked, and the old
    /// list keeps nothing when it comes back.
    func testAMoveLetsGoOfAListOnItsWayFromTheOldAddress() async throws {
        let held = HeldModels()
        let (model, server) = try makeModel(serving: held)
        let newURL = try XCTUnwrap(URL(string: "http://127.0.0.1:49979/v1"))
        model.registry.register(MockProvider(gglib: .serving("0.35.0")), at: newURL)
        let old = Task { await model.listModels(of: server, quietly: true) }
        for _ in 0..<5_000 where held.asked == 0 { await Task.yield() }
        XCTAssertEqual(held.asked, 1, "the list was never asked for")

        var moved = server
        moved.kind = .openAICompatible(baseURL: newURL)
        model.updateProvider(moved)
        let new = Task { await model.listModels(of: moved, quietly: true) }
        for _ in 0..<200 { await Task.yield() }
        held.release()
        await new.value
        await old.value
        XCTAssertEqual(model.models(for: server.id), MockProvider.sampleModels, "the new address was not asked")
        XCTAssertEqual(model.gglibAnswers[server.id], .server(.serving("0.35.0")), "the old list was kept")
    }

    /// A rename made while the list was asked for is kept when the list
    /// comes back and names the default model.
    func testARenameWhileTheModelsAreListedIsKept() async throws {
        let held = HeldModels()
        let (model, server) = try makeModel(serving: held)
        let listing = Task { await model.refreshModels(for: server, quietly: true) }
        for _ in 0..<5_000 where held.asked == 0 { await Task.yield() }
        XCTAssertEqual(held.asked, 1, "the list was never asked for")

        var renamed = server
        renamed.name = "desk"
        model.updateProvider(renamed)
        held.release()
        await listing.value

        let kept = try XCTUnwrap(model.providers.first)
        XCTAssertEqual(kept.name, "desk", "the list wrote the old name back")
        XCTAssertEqual(kept.defaultModel, MockProvider.sampleModels.first(where: \.chats)?.id)
    }
}
