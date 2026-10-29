import GGChatCore
import XCTest

@testable import GGChatUI

/// Leaving and coming back take turns. Each test names the line in
/// `AppModel.scene(_:)`, `turnDownloads` or `connectPipe` that fails it.
final class AppModelScenePhaseTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(registry: LoopbackProviderRegistry, connector: any PipeConnector) -> AppModel {
        let defaults = UserDefaults(suiteName: "AppModelScenePhaseTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    @MainActor
    private func addPipe(to model: AppModel, named name: String) throws -> ProviderConfig {
        let config = ProviderConfig(
            name: name, kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return config
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus?, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted { await Task.yield() }
    }

    /// Which sessions the gate produced still hold a bound port.
    @MainActor
    private func stillBound(_ gate: GatedConnector, _ registry: LoopbackProviderRegistry) -> [URL] {
        gate.sessions.map(\.baseURL).filter { registry.provider(for: $0) != nil }
    }

    /// Two pipes, both up, both hung up, then a resume whose dials are held
    /// open while a hang-up arrives. Sequential dials once let that resume
    /// go on to dial the second pipe after the hang-up had passed, leaving a
    /// live pipe behind. The hang-up now moves on the generation of every
    /// dial already out, and nothing it calls off is installed.
    @MainActor
    func testABackgroundDuringAResumeLeavesNoPipeBehind() async throws {
        let registry = LoopbackProviderRegistry()
        let gate = GatedConnector(registry: registry)
        let model = makeModel(registry: registry, connector: gate)
        let first = try addPipe(to: model, named: "home")
        let second = try addPipe(to: model, named: "studio")
        gate.release(2)
        await model.connectPipe(for: first)
        await model.connectPipe(for: second)
        await model.scene(.background).value
        XCTAssertNil(model.pipeSession(for: first.id))
        XCTAssertNil(model.pipeSession(for: second.id))

        let resume = model.scene(.foreground)
        await waitForStatus(.idle, model, first.id)
        XCTAssertEqual(model.pipeStatus(for: first.id), .idle, "the resume's first dial never went out")

        await model.scene(.background).value
        gate.open()
        await resume.value

        XCTAssertNil(model.pipeSession(for: first.id), "the held dial installed itself after the hang-up")
        XCTAssertNil(model.pipeSession(for: second.id), "the resume went on to dial after the hang-up")
        XCTAssertEqual(model.pipeStatus(for: first.id), .closed)
        XCTAssertEqual(model.pipeStatus(for: second.id), .closed)
        XCTAssertEqual(stillBound(gate, registry), [], "a pipe outlived the background")
    }

    /// The pipes are dialled together on the way back: both dials are out
    /// before either lands, so a machine that is asleep no longer keeps the
    /// other waiting for its dial to give up (#85).
    @MainActor
    func testAResumeDialsEveryPipeAtOnce() async throws {
        let registry = LoopbackProviderRegistry()
        let gate = GatedConnector(registry: registry)
        let model = makeModel(registry: registry, connector: gate)
        let first = try addPipe(to: model, named: "home")
        let second = try addPipe(to: model, named: "studio")
        gate.release(2)
        await model.connectPipe(for: first)
        await model.connectPipe(for: second)
        await model.scene(.background).value

        let resume = model.scene(.foreground)
        let bothOut = await gate.waitForArrivals(4)

        XCTAssertTrue(bothOut, "the second pipe was not dialled while the first's dial was still out")
        XCTAssertEqual(gate.sessions.count, 2, "a resume dial landed before the gate let it")
        XCTAssertEqual(model.pipeStatus(for: first.id), .idle)
        XCTAssertEqual(model.pipeStatus(for: second.id), .idle)
        gate.open()
        await resume.value
        await waitForStatus(.direct, model, first.id)
        await waitForStatus(.direct, model, second.id)
        XCTAssertNotNil(model.pipeSession(for: first.id))
        XCTAssertNotNil(model.pipeSession(for: second.id))
    }

    /// A hang-up that lands before the resume's dials go out calls every one
    /// of them off: nothing is dialled after it. Fails when the cancellation
    /// check in `resumeDial` is gone.
    @MainActor
    func testABackgroundBeforeTheResumeDialsCallsThemAllOff() async throws {
        let registry = LoopbackProviderRegistry()
        let gate = GatedConnector(registry: registry)
        let model = makeModel(registry: registry, connector: gate)
        let first = try addPipe(to: model, named: "home")
        let second = try addPipe(to: model, named: "studio")
        gate.release(2)
        await model.connectPipe(for: first)
        await model.connectPipe(for: second)
        await model.scene(.background).value

        let resume = model.scene(.foreground)
        let away = model.scene(.background)
        gate.open()
        await resume.value
        await away.value

        XCTAssertEqual(gate.arrivals, 2, "the resume dialled after the hang-up had called it off")
        XCTAssertNil(model.pipeSession(for: first.id))
        XCTAssertNil(model.pipeSession(for: second.id))
        XCTAssertEqual(model.pipeStatus(for: first.id), .closed)
        XCTAssertEqual(model.pipeStatus(for: second.id), .closed)
    }

    /// The third window, which the issue did not name: a dial a view started
    /// after the hang-up pass had already gone by. No hang-up will ever see
    /// it, so it has to hang itself up. Fails when only the `!isAway` guard
    /// in `connectPipe` is gone.
    @MainActor
    func testADialThatLandsWhileTheAppIsAwayHangsItselfUp() async throws {
        let registry = LoopbackProviderRegistry()
        let gate = GatedConnector(registry: registry)
        let model = makeModel(registry: registry, connector: gate)
        let config = try addPipe(to: model, named: "home")
        await model.scene(.background).value

        let dial = Task { await model.connectPipe(for: config) }
        await waitForStatus(.idle, model, config.id)
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle, "the dial never went out")
        gate.open()
        await dial.value

        XCTAssertNil(model.pipeSession(for: config.id), "a dial landed while the app was away and stayed")
        XCTAssertNil(model.statusTasks[config.id], "and left a status task nothing would cancel")
        XCTAssertEqual(stillBound(gate, registry), [], "its port is still bound")
    }

    /// The other race: a return during a hang-up that is still awaiting a
    /// session's shutdown. The old code skipped the provider as still
    /// installed and came back to nothing. Fails when the resume no longer
    /// waits for the hang-up in flight.
    @MainActor
    func testAReturnDuringAHangUpWaitsForItAndDialsAgain() async throws {
        let registry = LoopbackProviderRegistry()
        let connector = HeldShutdownConnector(registry: registry)
        let model = makeModel(registry: registry, connector: connector)
        let config = try addPipe(to: model, named: "home")
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertNotNil(model.pipeSession(for: config.id))

        let away = model.scene(.background)
        for _ in 0..<200 where connector.shutdownsStarted < 1 { await Task.yield() }
        XCTAssertEqual(connector.shutdownsStarted, 1, "the hang-up never reached the session")

        let back = model.scene(.foreground)
        connector.release()
        await away.value
        await back.value
        await waitForStatus(.direct, model, config.id)

        XCTAssertNotNil(model.pipeSession(for: config.id), "coming back during the hang-up left the pipe down")
        XCTAssertEqual(model.pipeStatus(for: config.id), .direct)
    }

    /// The downloads to this iPhone are paused beside the replies on the
    /// way out, and the library hears pauses and resumes in turn. The
    /// background pass puts the reply through This iPhone down, keeping its
    /// partial, and does not end until the pause has returned; a return
    /// while the pause is held resumes only once it has; and a background
    /// while that resume is held pauses only once it has. Fails when
    /// `scene(_:)` stops waiting for the pause, or `turnDownloads` stops
    /// waiting for the turn before.
    @MainActor
    func testTheDownloadsPauseBesideTheRepliesAndResumeInTurn() async throws {
        let registry = LoopbackProviderRegistry()
        let library = HeldLibrary()
        let defaults = UserDefaults(suiteName: "AppModelScenePhaseTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: GatedConnector(registry: registry),
            engine: MockEngine(registry: registry, provider: HangingProvider()), library: library,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        model.newConversation()
        await model.open(config).value
        let streaming = try XCTUnwrap(model.send("go"))
        defer { streaming.cancel() }
        let started = await waitUntil { model.liveReply?.content == "half " }
        XCTAssertTrue(started, "the reply never started")

        let away = model.scene(.background)
        let ended = Ended()
        let watching = Task {
            await away.value
            ended.yet = true
        }
        let pausing = await waitUntil { library.calls == ["pause"] }
        XCTAssertTrue(pausing, "the background did not pause the downloads: \(library.calls)")
        let kept = await waitUntil { model.selectedConversation?.messages.last?.isPartial == true }
        XCTAssertTrue(kept, "the reply through This iPhone was not put down beside the pause")
        XCTAssertFalse(ended.yet, "the background pass ended before the pause returned")

        let back = model.scene(.foreground)
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(library.calls, ["pause"], "a resume went out while the pause was held")
        library.release()
        await watching.value
        let resumed = await waitUntil { library.calls == ["pause", "resume"] }
        XCTAssertTrue(resumed, "coming back did not resume the downloads: \(library.calls)")

        let awayAgain = model.scene(.background)
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(library.calls, ["pause", "resume"], "a pause went out while the resume was held")
        library.release()
        await back.value
        let pausedAgain = await waitUntil { library.calls == ["pause", "resume", "pause"] }
        XCTAssertTrue(pausedAgain, "the second background did not pause after the resume: \(library.calls)")
        library.release()
        await awayAgain.value
    }

    /// Waits until `done` holds, on a clock, for
    /// `AppModelEngineTests.waitUntil`'s reason.
    @MainActor
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }
}

/// Whether a task the test watches has ended, read and written on the main
/// actor.
@MainActor
private final class Ended {
    var yet = false
}
