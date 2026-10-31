import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// Removing a model from this iPhone, walked on `MockLibrary` and
/// `MockEngine` sharing one catalogue: the chats on This iPhone that had it,
/// and This iPhone's default, are left with none, so a send asks for a model,
/// and they keep none when This iPhone opens again; other chats keep theirs;
/// an engine holding a model is put down for the removal, a reply through
/// it kept as Stop keeps it, and one holding none is left serving; a model
/// no longer listed is refused before anything is touched; and one the
/// library refuses keeps its files, the list, the chats and the default.
@MainActor
final class AppModelRemovalTests: XCTestCase {
    private let phoneRepo = "mock/phone-1.7b-GGUF"
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)

    /// What the library has installed, which the engine lists as its models.
    private let catalogue = MockLibrary.Catalogue()
    /// Where the model saves.
    private let store = InMemoryStore()

    /// The library, over ``catalogue``.
    private var library: MockLibrary { MockLibrary(catalogue: catalogue) }

    /// A model with This iPhone added on the mock engine's one model, over
    /// ``library`` and ``store``. `provider` answers at the engine's address
    /// in place of the mock's own, and the library refuses every removal
    /// when `refusing`.
    private func makeModel(
        provider: (any Provider)? = nil, refusing: Bool = false
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let watching = WatchingLibrary(inner: library, registry: registry, refusing: refusing)
        let defaults = UserDefaults(suiteName: "AppModelRemovalTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: MockEngine(registry: registry, provider: provider, catalogue: catalogue), library: watching,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        return (model, config)
    }

    /// Waits until `done` holds, for `AppModelEngineTests.waitUntil`'s
    /// reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// The mock engine's one model, as `model` reads it installed, which is
    /// the row a removal is asked from.
    private func phoneModel(in model: AppModel) async throws -> InstalledModel {
        await model.refreshInstalled()
        return try XCTUnwrap(model.onDevice.installed?.first { $0.name == MockEngine.model.id })
    }

    /// Downloads a second model to this iPhone, and answers its name.
    private func installSecond(in model: AppModel) async throws -> String {
        let offers = try await library.quantizations(repo: phoneRepo, reading: reading)
        let fits = try XCTUnwrap(offers.first { $0.name == "Q4_K_M" })
        let name = MockLibrary.installedName(repo: phoneRepo, quantization: fits.name)
        model.download(fits, of: phoneRepo)
        let installed = await waitUntil { model.onDevice.installed?.contains { $0.name == name } == true }
        XCTAssertTrue(installed, "the second model was never installed")
        return name
    }

    private func modelOf(_ id: UUID, in model: AppModel) -> String? {
        model.conversations.first { $0.id == id }?.model
    }

    /// Each chat on This iPhone that had the model, and This iPhone's
    /// default, have none, in the store as well as on screen, and a send
    /// there asks for a model rather than going to another.
    func testARemovedModelLeavesTheChatsAndTheDefaultThatHadItWithNone() async throws {
        let (model, config) = try makeModel()
        let first = model.newConversation(with: config)
        let second = model.newConversation(with: config)
        await model.open(config).value

        await model.removeInstalled(try await phoneModel(in: model))
        XCTAssertNil(model.onDevice.installedFailure)
        XCTAssertEqual(model.onDevice.installed, [])
        XCTAssertNil(modelOf(first.id, in: model), "a chat kept the model removed")
        XCTAssertNil(modelOf(second.id, in: model), "a chat kept the model removed")
        XCTAssertNil(model.providers.first?.defaultModel, "This iPhone kept the model removed as its default")
        let saved = try store.loadConversations()
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(saved.allSatisfy { $0.model == nil }, "the store kept the model removed for a chat")
        XCTAssertNil(try store.loadProviders().first?.defaultModel, "the store kept This iPhone's default")

        XCTAssertNil(model.send("hi"), "a chat with no model sent")
        XCTAssertEqual(model.lastError, "Pick a model first.")
    }

    /// A chat on This iPhone with another of its models, and a chat on a
    /// server whose model has the same name, keep theirs, as does the
    /// server's default; the engine, serving, lists its models again, and
    /// that does not make the model left This iPhone's default.
    func testARemovalLeavesTheOtherChatsAlone() async throws {
        let (model, config) = try makeModel()
        await model.open(config).value
        let other = try await installSecond(in: model)
        let gone = model.newConversation(with: config)
        let kept = model.newConversation(with: config)
        model.select(model: other, for: kept.id)
        let server = ProviderConfig(
            name: "desk", kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:49995/v1")!),
            defaultModel: MockEngine.model.id)
        try model.addProvider(server, credentials: [:])
        let elsewhere = model.newConversation(with: server)

        await model.removeInstalled(try await phoneModel(in: model))
        XCTAssertNil(modelOf(gone.id, in: model))
        XCTAssertNil(
            model.providers.first { $0.id == config.id }?.defaultModel,
            "the listing gave This iPhone the model left as its default")
        XCTAssertEqual(modelOf(kept.id, in: model), other, "a chat on another model lost it")
        XCTAssertEqual(modelOf(elsewhere.id, in: model), MockEngine.model.id, "a chat on a server lost its model")
        XCTAssertEqual(model.providers.first { $0.id == server.id }?.defaultModel, MockEngine.model.id)
        XCTAssertEqual(model.chatModels(for: config.id).map(\.id), [other])
    }

    /// An engine with the model loaded is put down before the files go, so
    /// nothing answers from a deleted file. The model leaves This iPhone's
    /// list though no engine is up to list it again, and when This iPhone
    /// opens again the engine serves afresh while the chat and the default
    /// still have no model: the model left is not made either by itself.
    func testARemovalPutsALoadedEngineDown() async throws {
        let (model, config) = try makeModel()
        await model.open(config).value
        let other = try await installSecond(in: model)
        let conversation = model.newConversation(with: config)
        try await XCTUnwrap(model.send("hi")).value
        let loaded = await waitUntil { model.engineStatus == .ready(model: MockEngine.model.id, nCtx: 4_096) }
        XCTAssertTrue(loaded, "the send loaded no model: \(String(describing: model.engineStatus))")
        let served = try XCTUnwrap(model.engineSession as? MockEngineSession)

        await model.removeInstalled(try await phoneModel(in: model))
        XCTAssertNil(model.engineSession, "the engine went on holding the model removed")
        XCTAssertNil(model.engineStatus)
        XCTAssertNil(model.registry.provider(for: MockEngine.baseURL), "the engine still answers")
        XCTAssertEqual(model.chatModels(for: config.id).map(\.id), [other], "the model removed is still listed")

        await model.open(config).value
        let again = try XCTUnwrap(model.engineSession as? MockEngineSession, "the engine was not served again")
        XCTAssertFalse(again === served)
        XCTAssertEqual(model.chatModels(for: config.id).map(\.id), [other])
        XCTAssertNil(modelOf(conversation.id, in: model), "the chat was given another model")
        XCTAssertNil(model.providers.first?.defaultModel, "This iPhone was given another default")
    }

    /// A reply going through the engine when its model is removed is put
    /// down as Stop puts it down, keeping what had arrived, before the
    /// engine goes, even while the engine's status has not yet said a model
    /// is loaded: the status follows the request, and is set back to idle
    /// here to stand for that. `HangingProvider` never ends a reply by
    /// itself.
    func testARemovalKeepsWhatAReplyThroughTheEngineHad() async throws {
        let (model, config) = try makeModel(provider: HangingProvider())
        model.newConversation(with: config)
        await model.open(config).value
        let streaming = try XCTUnwrap(model.send("go"))
        defer { streaming.cancel() }
        let started = await waitUntil { model.liveReply?.content == "half " }
        XCTAssertTrue(started, "the reply never started")
        model.setEngineStatus(.idle)

        await model.removeInstalled(try await phoneModel(in: model))
        XCTAssertTrue(model.liveReplies.isEmpty, "the reply outlived the engine it went through")
        XCTAssertNil(model.engineSession)
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.role, .assistant, "what had arrived was thrown away")
        XCTAssertEqual(last.content, "half ")
        XCTAssertTrue(last.isPartial)
        XCTAssertNil(last.failure, "a removal is not a failure, as a stop is not")
    }

    /// An engine serving with no model loaded is left serving, the same
    /// session, and lists its models again without the one removed.
    func testARemovalLeavesAnIdleEngineServing() async throws {
        let (model, config) = try makeModel()
        model.newConversation(with: config)
        await model.open(config).value
        let idle = await waitUntil { model.engineStatus == .idle }
        XCTAssertTrue(idle, "the engine was not idle: \(String(describing: model.engineStatus))")
        let served = try XCTUnwrap(model.engineSession as? MockEngineSession)

        await model.removeInstalled(try await phoneModel(in: model))
        XCTAssertTrue(model.engineSession as? MockEngineSession === served, "an engine holding no model was put down")
        XCTAssertEqual(model.engineStatus, .idle)
        XCTAssertEqual(model.chatModels(for: config.id), [])
    }

    /// A model no longer listed as installed is refused before anything is
    /// touched, with the library's sentence for one it does not have: a
    /// loaded engine stays up with its model, and the list, the chats, the
    /// default and a finished download's row stay as they were.
    func testARemovalOfAModelNoLongerListedTouchesNothing() async throws {
        let (model, config) = try makeModel()
        let conversation = model.newConversation(with: config)
        await model.open(config).value
        try await XCTUnwrap(model.send("hi")).value
        let ready = EngineStatus.ready(model: MockEngine.model.id, nCtx: 4_096)
        let loaded = await waitUntil { model.engineStatus == ready }
        XCTAssertTrue(loaded, "the send loaded no model: \(String(describing: model.engineStatus))")
        let served = try XCTUnwrap(model.engineSession as? MockEngineSession)
        let finished = QuantChoice(repo: phoneRepo, quantization: "Q8_0")
        model.onDevice.downloads[finished] = DownloadProgress(id: "", bytes: 1, total: 1, state: .done)
        var missing = try await phoneModel(in: model)
        let installed = model.onDevice.installed
        missing.id = 99

        await model.removeInstalled(missing)
        XCTAssertEqual(model.onDevice.installedFailure, OnDeviceError.notFound.localizedDescription)
        XCTAssertTrue(model.engineSession as? MockEngineSession === served, "a refused removal put the engine down")
        XCTAssertEqual(model.engineStatus, ready)
        XCTAssertEqual(model.onDevice.installed, installed)
        XCTAssertEqual(model.chatModels(for: config.id).map(\.id), [MockEngine.model.id])
        XCTAssertEqual(modelOf(conversation.id, in: model), MockEngine.model.id)
        XCTAssertEqual(model.providers.first?.defaultModel, MockEngine.model.id)
        XCTAssertEqual(model.onDevice.downloads[finished]?.state, .done, "a refused removal forgot a finished download")
    }

    /// A removal the library refuses says why under the section, and leaves
    /// the files, what is installed, This iPhone's list, its default and its
    /// chats, in the store too, as they were.
    func testARemovalTheLibraryRefusesKeepsTheFilesTheChatsAndTheDefault() async throws {
        let (model, config) = try makeModel(refusing: true)
        let conversation = model.newConversation(with: config)
        await model.open(config).value
        let idle = await waitUntil { model.engineStatus == .idle }
        XCTAssertTrue(idle, "the engine was not idle: \(String(describing: model.engineStatus))")
        let phone = try await phoneModel(in: model)
        let installed = model.onDevice.installed

        await model.removeInstalled(phone)
        XCTAssertEqual(model.onDevice.installedFailure, WatchingLibrary.refusal.localizedDescription)
        XCTAssertEqual(model.onDevice.installed, installed)
        XCTAssertEqual(catalogue.installed.map(\.name), [MockEngine.model.id])
        XCTAssertEqual(model.chatModels(for: config.id).map(\.id), [MockEngine.model.id])
        XCTAssertEqual(modelOf(conversation.id, in: model), MockEngine.model.id)
        XCTAssertEqual(model.providers.first?.defaultModel, MockEngine.model.id)
        XCTAssertEqual(try store.loadConversations().first?.model, MockEngine.model.id)
        XCTAssertEqual(try store.loadProviders().first?.defaultModel, MockEngine.model.id)
    }
}
