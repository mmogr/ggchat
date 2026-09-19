import GGChatCore
import XCTest

@testable import GGChatUI

/// What opening a conversation asks of its provider, and that the model, not
/// the view on screen, sees it through (#126).
final class AppModelOpeningTests: XCTestCase {
    /// modelpipe's normative vector 1, the shortest string that is a ticket.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(
        answeringAt host: String, sleeper: any Sleeper = ImmediateSleeper()
    ) -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(
            sleeper: sleeper, provider: ModelsServer.provider(at: host), registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelOpeningTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)))
        return (model, config)
    }

    /// A server added by address, answered by the same double.
    @MainActor
    private func makeAddressModel(answeringAt host: String) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let baseURL = URL(string: "http://\(host)/v1")!
        registry.register(ModelsServer.provider(at: host), at: baseURL)
        let defaults = UserDefaults(suiteName: "AppModelOpeningTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(registry: registry), diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(name: "server", kind: .openAICompatible(baseURL: baseURL))
        try model.addProvider(config, credentials: [:])
        return (model, config)
    }

    @MainActor
    private func add(_ config: ProviderConfig, to model: AppModel) throws {
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
    }

    /// Waits on the main actor, a little at a time, for something the model
    /// does in a task of its own, over a request answered on another thread.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor
    private func listed(_ model: AppModel, _ config: ProviderConfig) -> [String] {
        model.models(for: config.id).map(\.id)
    }

    /// A dial returns once the local port is bound, before the far machine
    /// answers, and this device's end of the pipe refuses a request in that
    /// gap. Asked then, the list got "no tunnel to the serving side is
    /// connected right now" and nothing asked again. The phone saw that on
    /// the first list of each of its two launches.
    @MainActor
    func testAPipeNotAnsweringYetWhenTheConversationOpensListsItsModelsOnceItIs() async throws {
        let host = "not-answering-yet.models.test"
        ModelsServer.answer(.refusing, at: host)
        let sleeper = HeldSleeper()
        defer { sleeper.release() }
        let (model, config) = makeModel(answeringAt: host, sleeper: sleeper)
        try add(config, to: model)

        await model.open(config).value
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle)
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 0, "asked while the pipe's end was still refusing")

        ModelsServer.answer(.listing, at: host)
        sleeper.release()
        await waitUntil { !listed(model, config).isEmpty }

        XCTAssertEqual(listed(model, config), ModelsServer.listed, "the pipe came up and nobody asked for the list")
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 1)
        XCTAssertNil(model.lastError)
    }

    /// The first conversation after pairing, over the pipe the code was
    /// redeemed through, which the app keeps as the provider's session.
    @MainActor
    func testAPipeTheCodeWasRedeemedOverListsItsModelsOnceItIsUp() async throws {
        let host = "paired.models.test"
        ModelsServer.answer(.listing, at: host)
        let sleeper = HeldSleeper()
        defer { sleeper.release() }
        let (model, config) = makeModel(answeringAt: host, sleeper: sleeper)
        try await model.addPairedProvider(config, pairing: "\(ticket)-123456", ticket: ticket, deviceName: nil)

        await model.open(config).value
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 0, "asked before the far machine answered")

        sleeper.release()
        await waitUntil { !listed(model, config).isEmpty }

        XCTAssertEqual(listed(model, config), ModelsServer.listed)
        XCTAssertNil(model.lastError)
    }

    /// A list that failed while the pipe was up is asked for again the next
    /// time the pipe comes up, and nothing on screen has to be opened again.
    /// A pipe coming up is nothing the person asked for, so its failure raises
    /// no alert. A list it already has is not asked for again.
    @MainActor
    func testAFollowedPipeThatComesBackAsksAgainForAListThatFailed() async throws {
        let host = "comes-back.models.test"
        ModelsServer.answer(.refusing, at: host)
        let sleeper = HeldSleeper()
        defer { sleeper.release() }
        let (model, config) = makeModel(answeringAt: host, sleeper: sleeper)
        try add(config, to: model)

        await model.open(config).value
        sleeper.release()
        // The pane is asked about only once the list's refusal is back, so
        // any alert it raised has been written by then.
        await waitUntil { ModelsServer.statusRequests(at: host) == 1 }
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 1, "the pipe came up and nobody asked for the list")
        XCTAssertTrue(listed(model, config).isEmpty)
        XCTAssertNil(model.lastError, "a list nobody asked for raised an alert when it failed")

        ModelsServer.answer(.listing, at: host)
        try await dropAndReconnect(config, of: model)
        await waitUntil { !listed(model, config).isEmpty }
        XCTAssertEqual(
            listed(model, config), ModelsServer.listed, "the pipe came back and the list was not asked again")
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 2)

        try await dropAndReconnect(config, of: model)
        await waitUntil { model.proxyStatusAvailable(for: config.id) }
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 2, "a list the pipe already had was asked for again")
        XCTAssertNil(model.lastError)
    }

    @MainActor
    private func dropAndReconnect(_ config: ProviderConfig, of model: AppModel) async throws {
        let session = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        session.dropped()
        await waitUntil { model.pipeStatus(for: config.id) == .closed }
        // The drop says why it closed; that sentence is not what this is about.
        model.lastError = nil
        await model.reconnectPipe(for: config)
        await waitUntil { model.pipeStatus(for: config.id) == .direct }
    }

    /// A server added by address has no pipe to wait for: opening its
    /// conversation lists its models and asks about its pane at once.
    @MainActor
    func testAServerAddedByAddressListsItsModelsAndIsAskedAboutItsPane() async throws {
        let host = "address.models.test"
        ModelsServer.answer(.listing, at: host)
        let (model, config) = try makeAddressModel(answeringAt: host)

        await model.open(config).value

        XCTAssertEqual(listed(model, config), ModelsServer.listed)
        XCTAssertEqual(ModelsServer.statusRequests(at: host), 1)
        XCTAssertTrue(model.proxyStatusAvailable(for: config.id))
        XCTAssertNil(model.lastError)
    }

    /// An opening that has finished is done with: opening the conversation
    /// again asks again, and a list that failed the first time, which the
    /// person was told about, gets its second try.
    @MainActor
    func testOpeningAgainAfterAnOpeningFinishedAsksAgain() async throws {
        let host = "again.models.test"
        ModelsServer.answer(.refusing, at: host)
        let (model, config) = try makeAddressModel(answeringAt: host)

        await model.open(config).value
        XCTAssertNotNil(model.lastError, "a list the person asked for failed and nothing said so")
        XCTAssertTrue(listed(model, config).isEmpty)
        model.lastError = nil

        ModelsServer.answer(.listing, at: host)
        await model.open(config).value

        XCTAssertEqual(listed(model, config), ModelsServer.listed, "the second opening did not ask again")
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 2)
        XCTAssertNil(model.lastError)
    }

    /// The alert #126 put in front of the person as they opened
    /// conversations: a request that failed only because the task asking for
    /// it was called off.
    @MainActor
    func testARefreshWhoseTaskWasCalledOffRaisesNoAlert() async throws {
        let host = "called-off.models.test"
        ModelsServer.answer(.holding, at: host)
        let (model, config) = makeModel(answeringAt: host)
        try add(config, to: model)
        await model.connectPipe(for: config)
        await waitUntil { model.pipeStatus(for: config.id) == .direct }

        let refresh = Task { await model.refreshModels(for: config) }
        await waitUntil { ModelsServer.modelRequests(at: host) == 1 }
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 1, "the refresh never reached the server")
        refresh.cancel()
        await refresh.value

        XCTAssertNil(model.lastError, "a refresh that was called off raised an alert")
        XCTAssertTrue(listed(model, config).isEmpty)
    }

    /// The heart of #126: SwiftUI can cancel the view task that opens a
    /// conversation as soon as it starts. The work is the model's, and runs
    /// to the end anyway.
    @MainActor
    func testOpeningIsNotCalledOffWithTheTaskThatAskedForIt() async throws {
        let host = "caller-gone.models.test"
        ModelsServer.answer(.listing, at: host)
        let (model, config) = makeModel(answeringAt: host)
        try add(config, to: model)
        // Up before the conversation opens, so no pulse follows to rescue
        // the list: the opening's own work is the only thing that asks.
        await model.connectPipe(for: config)
        await waitUntil { model.pipeStatus(for: config.id) == .direct }

        let caller = Task { @MainActor () -> Task<Void, Never> in
            withUnsafeCurrentTask { $0?.cancel() }
            return model.open(config)
        }
        await caller.value.value

        XCTAssertEqual(listed(model, config), ModelsServer.listed, "the opening was called off with its caller")
        XCTAssertNil(model.lastError)
    }

    /// A view can open the same conversation again at once; the second call
    /// joins the first rather than asking twice.
    @MainActor
    func testASecondOpeningWhileTheFirstRunsAsksNothingMore() async throws {
        let host = "twice.models.test"
        ModelsServer.answer(.holding, at: host)
        let (model, config) = makeModel(answeringAt: host)
        try add(config, to: model)
        await model.connectPipe(for: config)
        await waitUntil { model.pipeStatus(for: config.id) == .direct }

        let first = model.open(config)
        await waitUntil { ModelsServer.modelRequests(at: host) == 1 }
        let second = model.open(config)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(ModelsServer.modelRequests(at: host), 1, "a second opening asked for the list again")

        ModelsServer.release(at: host)
        await first.value
        await second.value
        XCTAssertEqual(listed(model, config), ModelsServer.listed)
    }

    /// The status pane, asked about again once a pipe a conversation is open
    /// on comes up, by the model and with no view involved.
    @MainActor
    func testThePaneIsAskedAboutWhenAFollowedPipeComesUp() async throws {
        let host = "pane.models.test"
        ModelsServer.answer(.listing, at: host)
        let sleeper = HeldSleeper()
        defer { sleeper.release() }
        let (model, config) = makeModel(answeringAt: host, sleeper: sleeper)
        try add(config, to: model)

        await model.open(config).value
        XCTAssertEqual(ModelsServer.statusRequests(at: host), 0)
        XCTAssertFalse(model.proxyStatusAvailable(for: config.id))

        sleeper.release()
        await waitUntil { model.proxyStatusAvailable(for: config.id) }

        XCTAssertTrue(model.proxyStatusAvailable(for: config.id), "the pipe came up and the pane was not asked about")
        XCTAssertEqual(ModelsServer.statusRequests(at: host), 1)
    }
}
