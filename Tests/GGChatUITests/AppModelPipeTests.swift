import GGChatCore
import XCTest

@testable import GGChatUI

final class AppModelPipeTests: XCTestCase {
    /// modelpipe's normative vector 1, the shortest string that is a ticket.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(
        script: MockProvider.Script = .init(text: "over the pipe")
    ) throws
        -> (AppModel, ProviderConfig)
    {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(
            sleeper: ImmediateSleeper(), provider: MockProvider(scripts: [script]), registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelPipeTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted {
            await Task.yield()
        }
    }

    @MainActor
    func testConnectWalksToDirectAndStreamsThroughTheSessionURL() async throws {
        let (model, config) = try makeModel()
        XCTAssertNil(model.pipeStatus(for: config.id))
        await model.connectPipe(for: config)
        let session = try XCTUnwrap(model.pipeSession(for: config.id))
        XCTAssertEqual(session.baseURL.host(), "127.0.0.1")
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.pipeStatus(for: config.id), .direct)
        XCTAssertEqual(model.connectedPulse, 1, "one haptic, on the first connected state")
        XCTAssertEqual(model.diagnostics.ticketDigests, [Ticket.digest(ticket)])

        model.newConversation()
        XCTAssertEqual(model.pipeStatus(for: try XCTUnwrap(model.selectedConversation)), .direct)
        let task = try XCTUnwrap(model.send("hello"))
        await task.value
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, "over the pipe")
    }

    @MainActor
    func testForceClosedIsCountedAndReconnectDialsAgain() async throws {
        let (model, config) = try makeModel()
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        let mock = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        mock.forceClosed()
        await waitForStatus(.closed, model, config.id)
        XCTAssertEqual(model.diagnostics.closedTransitions, 1)
        XCTAssertEqual(model.diagnostics.closedWhileStreaming, 0)

        await model.reconnectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.pipeStatus(for: config.id), .direct)
        XCTAssertEqual(model.connectedPulse, 2)
        XCTAssertEqual(model.diagnostics.ticketDigests.count, 1, "the same ticket is one node")
    }

    @MainActor
    func testConnectWithoutSecretsRefusesWithASentence() async throws {
        let (model, _) = try makeModel()
        let orphan = ProviderConfig(name: "orphan", kind: .pipe(ticketDigest: "x"))
        try model.addProvider(orphan, credentials: [:])
        await model.connectPipe(for: orphan)
        XCTAssertNil(model.pipeSession(for: orphan.id))
        XCTAssertEqual(model.lastError, "The ticket or token for orphan is missing from the Keychain.")
    }

    @MainActor
    func testRemovingAProviderShutsItsPipeDown() async throws {
        let (model, config) = try makeModel()
        await model.connectPipe(for: config)
        let session = try XCTUnwrap(model.pipeSession(for: config.id))
        model.removeProvider(config.id)
        for _ in 0..<200 where model.pipeSession(for: config.id) != nil { await Task.yield() }
        XCTAssertNil(model.pipeSession(for: config.id))
        var iterator = session.status.makeAsyncIterator()
        var last: PipeStatus? = await iterator.next()
        var drained = 0
        while last != nil, drained < 5 {
            last = await iterator.next()
            drained += 1
        }
        XCTAssertNil(last, "the session's status stream has finished")
    }
}
