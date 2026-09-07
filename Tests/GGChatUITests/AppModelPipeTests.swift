import GGChatCore
import XCTest

@testable import GGChatUI

final class AppModelPipeTests: XCTestCase {
    /// modelpipe's normative vector 1, the shortest string that is a ticket.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(
        behind provider: any Provider = MockProvider(scripts: [.init(text: "over the pipe")])
    ) throws
        -> (AppModel, ProviderConfig)
    {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(sleeper: ImmediateSleeper(), provider: provider, registry: registry)
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

    /// ADR 0002's numerator on the close it was written for: the far machine
    /// goes away while a reply is arriving. The reply is held open by a
    /// provider that never finishes, because `MockProvider` always reaches a
    /// terminal event and `finish(_:finished:)` clears `liveReply` when it
    /// does — so with the canned provider the reply is over before the close
    /// lands, and "mid-reply" cannot be observed at all.
    ///
    /// Nothing here cancels the stream: `forceClosed()` leaves the session's
    /// loopback provider registered, so the reply goes on hanging and is
    /// cancelled by this test rather than by the close.
    @MainActor
    func testAPipeThatGoesAwayMidReplyIsCountedAsAMidReplyClose() async throws {
        let (model, config) = try makeModel(behind: HangingProvider())
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        model.newConversation()
        let streaming = try XCTUnwrap(model.send("hello"))
        defer { streaming.cancel() }
        for _ in 0..<200 where model.liveReply?.content.isEmpty != false { await Task.yield() }
        XCTAssertEqual(model.liveReply?.content, "half ", "the reply never started")

        try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession).forceClosed()
        await waitForStatus(.closed, model, config.id)

        XCTAssertEqual(model.diagnostics.closedTransitions, 1)
        XCTAssertEqual(
            model.diagnostics.closedWhileStreaming, 1,
            "a close that arrived on the session's own status stream stopped being counted as mid-reply")
        XCTAssertTrue(
            model.isStreaming,
            "a close does not end the reply it interrupts, so nothing counted in finish(_:finished:) can be "
                + "asserted alongside this one")
    }

    /// A hang-up that leaves no pill is not a close. Deleting a provider and
    /// pressing reconnect both end a session, but neither shows the user a
    /// Closed pipe: the first leaves no provider and the second leaves a dial
    /// in flight. Counting them would put into "of M closes" two events that
    /// the user asked for and that no reading is about.
    @MainActor
    func testAHangUpThatLeavesNoPillIsNotCountedAsAClose() async throws {
        let (model, config) = try makeModel()
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)

        await model.reconnectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.diagnostics.closedTransitions, 0, "asking for the pipe back was counted as losing it")

        model.removeProvider(config.id)
        for _ in 0..<200 where model.pipeStatus(for: config.id) != nil { await Task.yield() }
        XCTAssertNil(model.pipeStatus(for: config.id))
        XCTAssertEqual(model.diagnostics.closedTransitions, 0, "deleting a machine was counted as a close")
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
