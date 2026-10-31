import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// What a removal of a model from this iPhone does about the engine around
/// it, walked on `WatchingLibrary`, which notes whether the engine still
/// answered as each removal reached it: a loaded engine is down before the
/// files go; a second removal while the first's shutdown is under way waits
/// for it too; and a send naming the model while it goes is refused rather
/// than loading it again.
@MainActor
final class AppModelRemovalRaceTests: XCTestCase {
    private let phoneRepo = "mock/phone-1.7b-GGUF"
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)
    private let registry = LoopbackProviderRegistry()
    /// What the library has installed.
    private let catalogue = MockLibrary.Catalogue()
    private var watching: WatchingLibrary!

    /// A model on `engine` with This iPhone added on the mock engine's one
    /// model and opened, over ``watching``.
    private func makeModel(engine: any LocalEngine) async throws -> (AppModel, ProviderConfig) {
        watching = WatchingLibrary(inner: MockLibrary(catalogue: catalogue), registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelRemovalRaceTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine, library: watching, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        model.newConversation(with: config)
        await model.open(config).value
        return (model, config)
    }

    /// Waits until `done` holds, for `AppModelEngineTests.waitUntil`'s
    /// reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// Sends, and waits until the engine has the mock's model loaded.
    private func load(_ model: AppModel) async throws {
        try await XCTUnwrap(model.send("hi")).value
        let loaded = await waitUntil { model.engineStatus == .ready(model: MockEngine.model.id, nCtx: 4_096) }
        XCTAssertTrue(loaded, "the send loaded no model: \(String(describing: model.engineStatus))")
    }

    /// The installed model called `name`, as `model` reads it.
    private func installed(_ name: String, in model: AppModel) async throws -> InstalledModel {
        await model.refreshInstalled()
        return try XCTUnwrap(model.onDevice.installed?.first { $0.name == name })
    }

    /// The engine with the model loaded has stopped answering by the time
    /// the library is asked to delete the files.
    func testTheEngineIsDownBeforeTheFilesGo() async throws {
        let (model, _) = try await makeModel(engine: MockEngine(registry: registry, catalogue: catalogue))
        try await load(model)

        await model.removeInstalled(try await installed(MockEngine.model.id, in: model))
        XCTAssertNil(model.onDevice.installedFailure)
        XCTAssertEqual(watching.engineAnsweredAtRemovals, [false], "the files went while the engine still answered")
    }

    /// A second removal while the first's shutdown is still under way joins
    /// it, and asks the library nothing until the engine is down: the status
    /// says nothing is loaded by then, and no reply goes through it.
    func testASecondRemovalWaitsForTheEngineTheFirstPutsDown() async throws {
        let engine = GatedEngine(registry: registry, holdingServes: false, holdingShutdowns: true)
        let (model, _) = try await makeModel(engine: engine)
        let offers = try await watching.quantizations(repo: phoneRepo, reading: reading)
        let fits = try XCTUnwrap(offers.first { $0.name == "Q4_K_M" })
        let other = MockLibrary.installedName(repo: phoneRepo, quantization: fits.name)
        model.download(fits, of: phoneRepo)
        let downloaded = await waitUntil { model.onDevice.installed?.contains { $0.name == other } == true }
        XCTAssertTrue(downloaded, "the second model was never installed")
        try await load(model)
        let phone = try await installed(MockEngine.model.id, in: model)
        let second = try await installed(other, in: model)

        let first = Task { await model.removeInstalled(phone) }
        let goingDown = await engine.waitForShutdowns(1)
        XCTAssertTrue(goingDown, "the first removal did not put the engine down")
        let following = Task { await model.removeInstalled(second) }
        let asked = await waitUntil(within: .milliseconds(200)) { !watching.engineAnsweredAtRemovals.isEmpty }
        XCTAssertFalse(asked, "a removal reached the library while the engine was still going down")
        engine.releaseShutdowns()
        await first.value
        await following.value

        XCTAssertEqual(watching.engineAnsweredAtRemovals, [false, false])
        XCTAssertEqual(model.onDevice.installed, [])
    }

    /// While a model is being removed a send naming it is refused with a
    /// sentence, rather than waiting for the engine and loading it again;
    /// once it is gone, the chat has no model.
    func testASendNamingAModelBeingRemovedIsRefused() async throws {
        let engine = GatedEngine(registry: registry, holdingServes: false, holdingShutdowns: true)
        let (model, _) = try await makeModel(engine: engine)
        try await load(model)
        let phone = try await installed(MockEngine.model.id, in: model)

        let removing = Task { await model.removeInstalled(phone) }
        let goingDown = await engine.waitForShutdowns(1)
        XCTAssertTrue(goingDown, "the removal did not put the engine down")
        XCTAssertNil(model.send("again"), "a send naming the model being removed went ahead")
        XCTAssertEqual(model.lastError, AppModel.beingRemoved(MockEngine.model.id))
        XCTAssertTrue(model.liveReplies.isEmpty, "a refused send is waiting for the engine")
        engine.releaseShutdowns()
        await removing.value

        XCTAssertNil(model.selectedConversation?.model)
        XCTAssertEqual(engine.serves, 1, "the engine was served again for the model being removed")
    }
}
