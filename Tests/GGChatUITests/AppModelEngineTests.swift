import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// A conversation on the provider that runs on this device's own engine,
/// walked on `MockEngine`: opening it serves the engine, a send goes the chat
/// route with gglib's progress asked for and is never a run, there is no Draw
/// switch, the engine's usage raises the ring, a model too big for the
/// device says where to pick another, and removing the provider takes the
/// engine down, a serve or a shutdown in flight included.
@MainActor
final class AppModelEngineTests: XCTestCase {
    private let ready = EngineStatus.ready(model: MockEngine.model.id, nCtx: 4_096)

    private func makeModel(engine: any LocalEngine, registry: LoopbackProviderRegistry) -> AppModel {
        let defaults = UserDefaults(suiteName: "AppModelEngineTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine, library: MockLibrary(),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// Waits, for up to `limit`, until `done` holds, and answers whether it
    /// did. Polled on a clock rather than counted in yields: a session goes
    /// down off the main actor, for `GatedConnector.waitForArrivals`'s
    /// reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// A model on the mock engine behaving so, with This iPhone added, a
    /// conversation open on it, and that opening finished. `provider`
    /// answers at the engine's address in place of the mock's own.
    private func makeOpenedModel(
        _ behaviour: MockEngine.Behaviour = .ready, provider: (any Provider)? = nil
    ) async throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let model = makeModel(
            engine: MockEngine(behaviour: behaviour, registry: registry, provider: provider), registry: registry)
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        model.newConversation()
        await model.open(config).value
        return (model, config)
    }

    /// Opening the conversation serves the engine once and lists its model,
    /// and loads none: the status is idle until a send names the model, which
    /// it follows to ready. Opening it again serves nothing more.
    func testOpeningThisIPhoneServesItsEngineOnceAndListsItsModel() async throws {
        let (model, config) = try await makeOpenedModel()
        let served = try XCTUnwrap(model.engineSession as? MockEngineSession)
        XCTAssertEqual(served.reading.physicalBytes, ProcessInfo.processInfo.physicalMemory)
        XCTAssertEqual(model.models(for: config.id).map(\.id), [MockEngine.model.id])
        _ = await waitUntil { model.engineStatus == .idle }
        XCTAssertEqual(model.engineStatus, .idle, "opening loaded a model")

        try await XCTUnwrap(model.send("hi")).value
        _ = await waitUntil { model.engineStatus == ready }
        XCTAssertEqual(model.engineStatus, ready)
        await model.open(config).value
        XCTAssertTrue(model.engineSession as? MockEngineSession === served, "a second opening served again")
    }

    /// The send goes the chat route with progress asked for, as gglib's
    /// does, to a hub that would take a run if it were asked one: it is not,
    /// and nothing asks it about drawing.
    func testASendOnThisIPhoneAsksForProgressAndIsNeverARun() async throws {
        let hub = FakeRunHub(frames: FakeRunHub.frames(ofText: "a run", reasoning: ""))
        let (model, config) = try await makeOpenedModel(provider: hub)
        XCTAssertNil(model.runHub(hub, for: config))

        try await XCTUnwrap(model.send("hi")).value
        XCTAssertTrue(hub.with(\.starts).isEmpty, "a reply on this iPhone was started as a run")
        let chats = hub.with(\.chats)
        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(chats.first?.returnProgress, true, "the engine is gglib and was not asked for progress")
        XCTAssertEqual(chats.first?.model, MockEngine.model.id)
        XCTAssertEqual(hub.with(\.drawingAsked), 0, "this iPhone was asked whether it draws")
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "the old way")
    }

    /// No Draw switch, and a question marked to draw is not kept so.
    func testThisIPhoneOffersNoDraw() async throws {
        let (model, _) = try await makeOpenedModel()
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertFalse(model.offersDrawing(for: conversation))
        XCTAssertEqual(model.drawRefusal(for: conversation), AppModel.needsAPairedMac)
        let asked = try XCTUnwrap(model.appendTurn("draw a cat", images: [], draws: true))
        XCTAssertEqual(asked.messages.last?.draws, false)
    }

    /// The engine's reply reports the context it loaded beside its counts,
    /// and that is the reading the conversation keeps and the ring draws.
    func testTheRingLandsFromTheEnginesUsage() async throws {
        let (model, _) = try await makeOpenedModel()
        try await XCTUnwrap(model.send("hi")).value
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(conversation.context?.size, 4_096)
        XCTAssertEqual(conversation.context?.model, MockEngine.model.id)
        XCTAssertNotNil(model.contextReading(for: conversation), "a reply on this iPhone raised no ring")
    }

    /// A model too big for the device is refused before its first token, and
    /// the line under the refusal says where to pick a smaller one.
    func testATooBigModelIsRefusedWithAdviceForThisIPhone() async throws {
        let (model, _) = try await makeOpenedModel(.tooBig)
        try await XCTUnwrap(model.send("hi")).value
        let conversation = try XCTUnwrap(model.selectedConversation)
        let failure = try XCTUnwrap(conversation.messages.last?.failure)
        XCTAssertEqual(failure.code, ProviderError.Code.modelDoesNotFit.rawValue)
        XCTAssertEqual(
            model.advice(for: failure, in: conversation),
            "Pick a smaller model for This iPhone from the model list under the chat.")
    }

    /// With no engine in the build, the conversation still opens, but a send
    /// is refused at once with a sentence about the build, and nothing waits.
    func testWithNoEngineASendOnThisIPhoneIsRefusedWithASentence() async throws {
        let model = makeModel(engine: UnavailableEngine(), registry: LoopbackProviderRegistry())
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        model.newConversation()
        await model.open(config).value
        XCTAssertNil(model.engineSession)

        XCTAssertNil(model.send("hi"))
        XCTAssertEqual(model.lastError, OnDeviceError.engineUnavailable.errorDescription)
        XCTAssertTrue(model.liveReplies.isEmpty, "a send on an engine this build lacks is waiting")
    }

    /// One engine, so one provider for it, however often it is asked for.
    func testThisIPhoneIsAddedOnce() throws {
        let model = makeModel(engine: MockEngine(registry: LoopbackProviderRegistry()), registry: .init())
        let first = try model.addThisIPhone(defaultModel: nil)
        let second = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(model.providers.map(\.kind), [.onDevice])
        XCTAssertEqual(model.providers.first?.name, "This iPhone")
    }

    /// Removing the provider takes its engine down: the session ends and
    /// nothing answers at its address.
    func testRemovingThisIPhoneTakesItsEngineDown() async throws {
        let (model, config) = try await makeOpenedModel()
        XCTAssertNotNil(model.registry.provider(for: MockEngine.baseURL))
        model.removeProvider(config.id)
        _ = await waitUntil { model.engineSession == nil && model.registry.provider(for: MockEngine.baseURL) == nil }
        XCTAssertNil(model.engineSession)
        XCTAssertNil(model.registry.provider(for: MockEngine.baseURL), "the engine still answers")
    }

    /// Removed while its engine is still starting, the provider takes down
    /// the session that serve lands, rather than finding none and leaving
    /// it serving with no provider.
    func testRemovingThisIPhoneWhileItsEngineStartsLeavesNothingServing() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(registry: registry, holdingServes: true, holdingShutdowns: false)
        let model = makeModel(engine: engine, registry: registry)
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        model.newConversation()
        let opening = model.open(config)
        let serving = await engine.waitForServes(1)
        XCTAssertTrue(serving, "the engine was never served")

        model.removeProvider(config.id)
        let shuttingDown = await waitUntil { model.engineShuttingDown != nil }
        XCTAssertTrue(shuttingDown, "removing This iPhone did not take its engine down")
        engine.releaseServes()
        await opening.value

        _ = await waitUntil { model.engineSession == nil && registry.provider(for: MockEngine.baseURL) == nil }
        XCTAssertNil(model.engineSession, "a session is up with no provider for it")
        XCTAssertNil(registry.provider(for: MockEngine.baseURL), "the engine still answers with no provider")
    }

    /// A serve asked for while the last session is still going down waits
    /// until it is down, so the old session's unbinding cannot take the new
    /// one's address: This iPhone removed, added again and opened.
    func testAServeWhileTheEngineGoesDownWaitsUntilItIsDown() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(registry: registry, holdingServes: false, holdingShutdowns: true)
        let model = makeModel(engine: engine, registry: registry)
        let first = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        await model.open(first).value
        let gone = try XCTUnwrap(model.engineSession as? GatedEngineSession)
        model.removeProvider(first.id)
        let goingDown = await engine.waitForShutdowns(1)
        XCTAssertTrue(goingDown, "removing This iPhone did not take its engine down")

        let again = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        let opening = model.open(again)
        let servedEarly = await engine.waitForServes(2, within: .milliseconds(200))
        XCTAssertFalse(servedEarly, "the engine was served again while its last session was going down")
        engine.releaseShutdowns()
        await opening.value
        _ = await waitUntil { model.engineShuttingDown == nil }

        let served = try XCTUnwrap(model.engineSession as? GatedEngineSession, "the engine was not served again")
        XCTAssertFalse(served === gone, "the session that went down is still the one kept")
        XCTAssertNotNil(registry.provider(for: MockEngine.baseURL), "the old session unbound the new one's address")
    }
}
