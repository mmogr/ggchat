import Foundation
import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// Two quantizations of one model on this iPhone, which gglib installs under
/// one name and two ids: each is its own row in the model list, picked and
/// sent by its id, the pill follows the one the engine holds by its id, and
/// removing one leaves the other, its chats and an engine holding it alone.
/// The mock engine's model is id 1, and a second quantization of it, under
/// the same name, id 2; the mock engine always loads id 1.
@MainActor
final class ThisIPhoneTwinsTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let calendar = Calendar(identifier: .gregorian)
    private let modelName = MockEngine.model.id

    /// A model with This iPhone added on id 1, over a library holding the
    /// twins, whose engine answers through `provider` when it is given.
    private func makeModel(provider: (any Provider)? = nil) async throws -> (AppModel, ProviderConfig) {
        let catalogue = MockLibrary.Catalogue()
        let library = MockLibrary(catalogue: catalogue)
        let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)
        let offers = try await library.quantizations(repo: MockLibrary.phoneRepo, reading: reading)
        catalogue.install(try XCTUnwrap(offers.first { $0.label == "Q8_0" }), of: MockLibrary.phoneRepo, as: modelName)
        XCTAssertEqual(catalogue.installed.map(\.id), [1, 2])
        XCTAssertEqual(Set(catalogue.installed.map(\.name)), [modelName])
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: MockEngine(registry: registry, provider: provider, catalogue: catalogue), library: library,
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "ThisIPhoneTwinsTests.\(UUID().uuidString)")!),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = try model.addThisIPhone(defaultModel: "1")
        await model.refreshInstalled()
        return (model, config)
    }

    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// The twins are two rows, keyed 1 and 2, and only the chat's is ticked,
    /// before the engine has listed anything; the chat shows the model's
    /// name, not its id. Picking the second ticks it alone and sends "2".
    func testTwoQuantizationsOfOneModelAreTwoChoices() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "fine")]))
        let (model, config) = try await makeModel(provider: recorder)
        let conversation = model.newConversation(with: config)
        XCTAssertNil(model.engineSession, "the engine was served to read the model list")
        XCTAssertEqual(model.shownModelName(for: conversation), modelName)

        var rows = try XCTUnwrap(
            model.modelListSections(for: conversation, locale: english, calendar: calendar)
                .first { $0.id == config.id }
        ).rows
        XCTAssertEqual(rows.map(\.modelID), ["1", "2"])
        XCTAssertEqual(rows.map(\.name), [modelName, "\(modelName) · Q8_0"])
        XCTAssertEqual(rows.map(\.isCurrent), [true, false])

        model.pick(model: "2", on: config.id, for: conversation.id)
        let picked = try XCTUnwrap(model.selectedConversation)
        rows = try XCTUnwrap(
            model.modelListSections(for: picked, locale: english, calendar: calendar)
                .first { $0.id == config.id }
        ).rows
        XCTAssertEqual(rows.map(\.isCurrent), [false, true], "picking one twin ticked the other")
        try await XCTUnwrap(model.send("hi")).value
        XCTAssertEqual(recorder.requests.last?.model, "2", "the request did not name the twin picked")
    }

    /// The engine holding id 1 reads as ready on a chat with id 1 and not
    /// loaded on one with id 2, though both have the same name.
    func testThePillFollowsTheTwinTheEngineHolds() async throws {
        let (model, config) = try await makeModel()
        let other = model.newConversation(with: config)
        model.select(model: "2", for: other.id)
        let conversation = model.newConversation(with: config)
        await model.open(config).value
        try await XCTUnwrap(model.send("hi")).value
        let ready = await waitUntil { model.sessionStatus(for: conversation) == .engine(.ready) }
        XCTAssertTrue(ready, "the pill did not say id 1 was ready: \(String(describing: model.engineStatus))")
        let twin = try XCTUnwrap(model.conversations.first { $0.id == other.id })
        XCTAssertEqual(model.sessionStatus(for: twin), .engine(.notLoaded), "the twin read as the model loaded")
    }

    /// Removing id 2 while the engine holds id 1 leaves the engine serving,
    /// the chat on id 1 and the default as they were, and only the chat on
    /// id 2 with no model.
    func testRemovingOneTwinLeavesTheOther() async throws {
        let (model, config) = try await makeModel()
        let twin = model.newConversation(with: config)
        model.select(model: "2", for: twin.id)
        let conversation = model.newConversation(with: config)
        await model.open(config).value
        try await XCTUnwrap(model.send("hi")).value
        let loaded = await waitUntil { model.sessionStatus(for: conversation) == .engine(.ready) }
        XCTAssertTrue(loaded, "the send loaded no model")
        let served = try XCTUnwrap(model.engineSession as? MockEngineSession)

        await model.removeInstalled(try XCTUnwrap(model.onDevice.installed?.first { $0.id == 2 }))
        XCTAssertTrue(
            (model.engineSession as? MockEngineSession) === served,
            "removing the twin put down the engine holding the other")
        XCTAssertEqual(model.onDevice.installed?.map(\.id), [1])
        XCTAssertEqual(model.conversations.first { $0.id == conversation.id }?.model, "1", "the other's chat lost it")
        XCTAssertNil(model.conversations.first { $0.id == twin.id }?.model, "the twin's chat kept the model removed")
        XCTAssertEqual(model.providers.first { $0.id == config.id }?.defaultModel, "1")
    }
}
