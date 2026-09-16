import GGChatCore
import XCTest

@testable import GGChatUI

/// Leaving and coming back take turns. Each test names the line in
/// `AppModel.scene(_:)` or `connectPipe` that fails it.
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

    /// Two pipes, both up, both hung up, then a resume whose first dial is
    /// held open while a hang-up arrives. The old code let that resume go on
    /// to dial the second pipe after the hang-up had passed, leaving a live
    /// pipe behind. Fails when both the cancellation check in
    /// `resumeEveryPipe` and the `!isAway` guard in `connectPipe` are gone.
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

    /// The same shape, asserting on what went out rather than what was left:
    /// the second pipe was never dialled at all. Fails when only the
    /// cancellation check in `resumeEveryPipe` is gone.
    @MainActor
    func testABackgroundStopsAResumeBeforeItsNextDial() async throws {
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
        await waitForStatus(.idle, model, first.id)
        await model.scene(.background).value
        gate.open()
        await resume.value

        XCTAssertEqual(
            gate.arrivals, 3,
            "the gate should have seen the two opening dials and the resume's first; the resume dialled on")
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
}
