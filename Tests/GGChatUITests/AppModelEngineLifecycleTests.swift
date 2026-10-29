import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// When this device's engine runs (ADR 0015), walked on `GatedEngine`, which
/// holds a serve or a shutdown open where a test needs the window: a send
/// waits for the engine and through its load, the background puts it down
/// only after the replies, a serve landing while the app is away takes
/// itself down, coming back starts nothing, a memory warning spares a reply,
/// a send that joined a serve put down serves afresh, Load again serves
/// afresh and asks again, and a refused serve says why under the question.
@MainActor
final class AppModelEngineLifecycleTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    private func makeModel(
        engine: any LocalEngine, registry: LoopbackProviderRegistry, connector: (any PipeConnector)? = nil
    ) -> AppModel {
        let defaults = UserDefaults(suiteName: "AppModelEngineLifecycleTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector ?? MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine, library: MockLibrary(), diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// Waits, for up to `limit`, until `done` holds, and answers whether it
    /// did, for `AppModelEngineTests.waitUntil`'s reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// This iPhone added, with a conversation open on it that has not been
    /// opened: nothing is served until the test asks.
    private func addThisIPhone(to model: AppModel) throws -> (ProviderConfig, Conversation) {
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        return (config, model.newConversation(with: config))
    }

    private func status(_ model: AppModel, _ conversation: Conversation) -> SessionStatus? {
        model.sessionStatus(for: conversation)
    }

    /// A send with the engine not serving waits for it, saying so, then goes
    /// out once it serves; the model loads within that request, the pill
    /// walking through it, and the reply streams only once it has loaded.
    func testASendWaitsForTheEngineThroughItsLoadThenReplies() async throws {
        let registry = LoopbackProviderRegistry()
        let sleeper = GatedSleeper()
        let engine = GatedEngine(
            registry: registry, holdingServes: true, holdingShutdowns: false, sleeper: sleeper,
            provider: MockProvider(contextSize: MockEngine.contextSize))
        let model = makeModel(engine: engine, registry: registry)
        let (config, conversation) = try addThisIPhone(to: model)

        let replying = try XCTUnwrap(model.send("hi"), "a send with the engine not serving was refused")
        let live = try XCTUnwrap(model.liveReply)
        XCTAssertEqual(live.waitingFor, config.id, "the send did not wait for the engine")
        XCTAssertEqual(
            model.waitingLine(for: live, locale: Locale(identifier: "en_US"), calendar: .current),
            "Waiting for This iPhone to start its engine")
        XCTAssertEqual(status(model, conversation), .engine(.notLoaded))
        let served = await engine.waitForServes(1)
        XCTAssertTrue(served, "the waiting send did not serve the engine")

        engine.releaseServes()
        let asked = await waitUntil { live.waitingFor == nil }
        XCTAssertTrue(asked, "the send did not go out once the engine served")
        await sleeper.release()
        let loading = await waitUntil { self.status(model, conversation) == .engine(.loading(fraction: 0.5)) }
        XCTAssertTrue(
            loading, "the pill did not say the model was loading: \(String(describing: status(model, conversation)))")
        XCTAssertEqual(live.content, "", "the reply streamed before the model had loaded")

        await sleeper.release()
        await replying.value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, MockProvider.sampleScript.text)
        let ready = await waitUntil { self.status(model, conversation) == .engine(.ready) }
        XCTAssertTrue(ready, "the pill did not say the model was ready")
        XCTAssertEqual(engine.serves, 1)
    }

    /// The background puts the reply down and waits for it, keeping what had
    /// arrived with Continue, before the engine is put down; the engine is
    /// down, and nothing answers at its address, by the pass's end.
    func testTheBackgroundPutsTheEngineDownOnlyOnceTheReplyHasEnded() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(
            registry: registry, holdingServes: false, holdingShutdowns: true, provider: HangingProvider())
        let model = makeModel(engine: engine, registry: registry)
        let (config, _) = try addThisIPhone(to: model)
        await model.open(config).value
        let streaming = try XCTUnwrap(model.send("go"))
        defer { streaming.cancel() }
        let started = await waitUntil { model.liveReply?.content == "half " }
        XCTAssertTrue(started, "the reply never started")

        let away = model.scene(.background)
        let goingDown = await engine.waitForShutdowns(1)
        XCTAssertTrue(goingDown, "the background did not put the engine down")
        XCTAssertTrue(model.liveReplies.isEmpty, "the engine was put down before the reply had ended")
        let kept = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(kept.role, .assistant)
        XCTAssertTrue(kept.isPartial, "the reply's partial was not kept with Continue")
        XCTAssertEqual(kept.content, "half ")

        engine.releaseShutdowns()
        await away.value
        XCTAssertNil(model.engineSession)
        XCTAssertNil(registry.provider(for: MockEngine.baseURL), "the engine still answers in the background")
    }

    /// A serve that lands while the app is away, after the background pass
    /// has begun and before it reaches the engine, takes its own session
    /// down: the pass is still hanging up a pipe when it does.
    func testAServeThatLandsWhileAwayTakesItselfDown() async throws {
        let registry = LoopbackProviderRegistry()
        let connector = HeldShutdownConnector(registry: registry)
        let engine = GatedEngine(registry: registry, holdingServes: true, holdingShutdowns: false)
        let model = makeModel(engine: engine, registry: registry, connector: connector)
        let home = ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "m")
        try model.addProvider(home, credentials: [.ticket: ticket, .token: "secret-token"])
        await model.connectPipe(for: home)
        let (config, _) = try addThisIPhone(to: model)
        let opening = model.open(config)
        let serving = await engine.waitForServes(1)
        XCTAssertTrue(serving, "opening did not serve the engine")

        let away = model.scene(.background)
        let hangingUp = await waitUntil { connector.shutdownsStarted == 1 }
        XCTAssertTrue(hangingUp, "the background pass never reached the pipe")
        engine.releaseServes()
        await opening.value
        let tookItselfDown = await waitUntil { engine.shutdowns == 1 }
        XCTAssertTrue(tookItselfDown, "a serve that landed while away kept its session")
        XCTAssertNil(model.engineSession, "a session served while away was kept")
        XCTAssertNil(registry.provider(for: MockEngine.baseURL), "the late session still answers")

        connector.release()
        await away.value
        XCTAssertEqual(engine.shutdowns, 1, "the late session was taken down twice")
    }

    /// Nothing is served while the app is away, an opening included, and
    /// coming back to the foreground serves nothing; the next send waits for
    /// a serve, and is answered.
    func testComingBackStartsNothingAndTheNextSendServesAgain() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(registry: registry, holdingServes: false, holdingShutdowns: false)
        let model = makeModel(engine: engine, registry: registry)
        let (config, conversation) = try addThisIPhone(to: model)
        await model.open(config).value
        XCTAssertEqual(engine.serves, 1)

        await model.scene(.background).value
        XCTAssertNil(model.engineSession, "the background left the engine up")
        await model.open(config).value
        XCTAssertEqual(engine.serves, 1, "an opening served the engine while the app was away")
        await model.scene(.foreground).value
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(engine.serves, 1, "coming back served the engine")
        XCTAssertNil(model.engineSession)
        XCTAssertEqual(status(model, conversation), .engine(.notLoaded))

        try await XCTUnwrap(model.send("hi"), "a send after coming back was refused").value
        XCTAssertEqual(engine.serves, 2, "the send did not serve the engine again")
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, MockProvider.sampleScript.text)
    }

    /// A memory warning leaves the engine up while a reply goes through it,
    /// and puts it down, freeing the model, once none does.
    func testAMemoryWarningPutsTheEngineDownOnlyWithNoReplyGoingThroughIt() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(
            registry: registry, holdingServes: false, holdingShutdowns: false, provider: HangingProvider())
        let model = makeModel(engine: engine, registry: registry)
        let (config, conversation) = try addThisIPhone(to: model)
        XCTAssertNil(model.memoryWarning(), "a memory warning with no engine up did something")
        await model.open(config).value
        let streaming = try XCTUnwrap(model.send("go"))
        defer { streaming.cancel() }
        let started = await waitUntil { model.liveReply?.content == "half " }
        XCTAssertTrue(started, "the reply never started")

        XCTAssertNil(model.memoryWarning(), "a memory warning put the engine down under a reply")
        XCTAssertNotNil(model.engineSession)
        model.stop(conversation.id)
        let stopped = await waitUntil { model.liveReplies.isEmpty }
        XCTAssertTrue(stopped, "the reply did not stop")

        try await XCTUnwrap(model.memoryWarning(), "a memory warning with no reply left the engine up").value
        XCTAssertNil(model.engineSession)
        XCTAssertNil(registry.provider(for: MockEngine.baseURL), "the engine still answers")
        XCTAssertEqual(engine.shutdowns, 1)
    }

    /// A memory warning while an opening's serve is under way puts that
    /// serve's session down as it lands; a send that joined the serve meanwhile
    /// is woken as it ends, serves the engine afresh and is answered.
    func testASendJoiningAServeAMemoryWarningPutsDownServesAgain() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(registry: registry, holdingServes: true, holdingShutdowns: false)
        let model = makeModel(engine: engine, registry: registry)
        let (config, conversation) = try addThisIPhone(to: model)
        let opening = model.open(config)
        let serving = await engine.waitForServes(1)
        XCTAssertTrue(serving, "opening did not serve the engine")
        let warned = try XCTUnwrap(model.memoryWarning(), "a memory warning during a serve did nothing")
        let replying = try XCTUnwrap(model.send("hi"), "a send during a serve was refused")
        let joined = await waitUntil { model.engineShuttingDown != nil && model.sessionWaits[conversation.id] != nil }
        XCTAssertTrue(joined, "the memory warning or the send never reached the engine")
        XCTAssertEqual(engine.serves, 1, "the send served the engine beside the serve under way")

        engine.releaseServes()
        let answered = await waitUntil { model.liveReplies.isEmpty }
        XCTAssertTrue(answered, "the send still waits for the engine after the serve it joined was put down")
        guard answered else { return replying.cancel() }
        await opening.value
        await warned.value
        await replying.value
        XCTAssertEqual(engine.serves, 2, "the send did not serve the engine again")
        XCTAssertEqual(engine.shutdowns, 1, "the serve put down did not take its own session down")
        XCTAssertNotNil(model.engineSession)
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, MockProvider.sampleScript.text)
    }

    /// The model fails to load: the pill says Load again, and pressing it
    /// serves the engine afresh and asks the question again, which loads the
    /// model and is answered.
    func testLoadAgainServesAfreshAndAsksTheQuestionAgain() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = GatedEngine(
            registry: registry, holdingServes: false, holdingShutdowns: false, behaviours: [.fails, .ready])
        let model = makeModel(engine: engine, registry: registry)
        let (config, conversation) = try addThisIPhone(to: model)
        await model.open(config).value
        try await XCTUnwrap(model.send("hi")).value
        let question = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(question.role, .user)
        XCTAssertNotNil(question.failure, "a load that failed left no failure on the question")
        let failed = await waitUntil { self.status(model, conversation) == .engine(.failed) }
        XCTAssertTrue(failed, "the pill does not offer Load again")
        XCTAssertTrue(model.offersPress(on: .engine(.failed), in: conversation))

        try await XCTUnwrap(model.press(.engine(.failed), in: conversation), "Load again did nothing").value
        XCTAssertEqual(engine.serves, 2, "Load again did not serve the engine afresh")
        XCTAssertEqual(engine.shutdowns, 1, "Load again did not put the failed engine down first")
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.count, 2, "the question was not asked again, or was asked twice")
        XCTAssertNil(messages.first?.failure, "the question kept its failure")
        XCTAssertEqual(messages.last?.content, MockProvider.sampleScript.text)
        let ready = await waitUntil { self.status(model, conversation) == .engine(.ready) }
        XCTAssertTrue(ready, "the pill did not say the model was ready")
    }

    /// A serve the engine refuses ends a send waiting for it with the
    /// engine's sentence under the question, and no alert.
    func testARefusedServePutsItsSentenceUnderTheWaitingQuestion() async throws {
        let model = makeModel(engine: RefusingEngine(), registry: LoopbackProviderRegistry())
        _ = try addThisIPhone(to: model)
        try await XCTUnwrap(model.send("hi")).value
        let question = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(question.failure?.message, RefusingEngine.sentence)
        XCTAssertNil(model.lastError, "the refusal was an alert as well")
        XCTAssertTrue(model.liveReplies.isEmpty)
    }
}

/// An engine whose every serve is refused, as gglib's is when it cannot bind
/// a port.
private struct RefusingEngine: LocalEngine {
    static let sentence = "The engine could not start: no port was free."

    var isAvailable: Bool { true }

    func serve(reading: DeviceReading) async throws -> any EngineSession {
        throw OnDeviceError.internal(message: Self.sentence)
    }
}
