import GGChatCore
import XCTest

@testable import GGChatUI

/// A reply to gglib is a run the hub owns: the background walks away from it,
/// coming back reads on, and only Stop cancels it.
final class AppModelRunTests: XCTestCase {
    static let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    static let text = "It reads the file and finds the longest line."
    static let reasoning = "Keep it short."

    /// A model with a pipe to `hub`, dialled, and a conversation open on it.
    @MainActor
    static func makeModel(
        behind hub: any Provider, store: any Store = InMemoryStore()
    ) async throws -> (
        AppModel, ProviderConfig
    ) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelRunTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: hub, registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        await model.connectPipe(for: config)
        try await until { model.pipeStatus(for: config.id) == .direct }
        model.newConversation()
        return (model, config)
    }

    /// Yields until `condition` holds, and fails the test when it never does.
    @MainActor
    static func until(
        _ what: String = "the condition", file: StaticString = #filePath, line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<5_000 where !condition() { await Task.yield() }
        if !condition() { XCTFail("\(what) never held", file: file, line: line) }
    }

    /// The last message of the open conversation.
    @MainActor
    static func last(_ model: AppModel) throws -> Message {
        try XCTUnwrap(model.selectedConversation?.messages.last)
    }

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Self.text, reasoning: Self.reasoning))
    }

    /// A send to gglib starts one run, under an id this device minted, and
    /// reads it from the start to a finished reply that keeps no run. A
    /// server not known to be gglib is sent the chat request as before.
    @MainActor
    func testASendToGGLibIsARunAndAnythingElseGoesTheOldWay() async throws {
        let hub = hub()
        let (model, _) = try await Self.makeModel(behind: hub)
        try await XCTUnwrap(model.send("go")).value
        let reply = try Self.last(model)
        XCTAssertEqual(reply.content, Self.text)
        XCTAssertEqual(reply.reasoning, Self.reasoning)
        XCTAssertFalse(reply.isPartial)
        XCTAssertNil(reply.runID)
        XCTAssertNil(reply.runCursor)
        let started = hub.with { $0.starts }
        XCTAssertEqual(started.count, 1)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(started.first?.id)), "the run's id is not a UUID string")
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0])
        XCTAssertEqual(hub.with { $0.chats.count }, 0)

        let server = self.hub()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49997/v1"))
        model.registry.register(server, at: url)
        let other = ProviderConfig(name: "server", kind: .openAICompatible(baseURL: url), defaultModel: "m")
        try model.addProvider(other, credentials: [:])
        var conversation = model.newConversation()
        conversation.providerID = other.id
        model.update(conversation)
        try await XCTUnwrap(model.send("go")).value
        XCTAssertEqual(server.with { $0.starts.count }, 0, "a server not known to be gglib was sent a run")
        XCTAssertEqual(server.with { $0.chats.count }, 1)
    }

    /// A hub that answers as an older gglib is sent the reply the old way
    /// with nothing shown, and is not asked again while the app runs.
    @MainActor
    func testAHubWithoutRunsIsAskedOnceAndTheReplyGoesTheOldWay() async throws {
        let hub = hub()
        hub.with { $0.start = .unsupported }
        let (model, _) = try await Self.makeModel(behind: hub)
        try await XCTUnwrap(model.send("one")).value
        try await XCTUnwrap(model.send("two")).value
        XCTAssertEqual(hub.with { $0.starts.count }, 1, "the fallback was paid for more than once")
        XCTAssertEqual(hub.with { $0.chats.count }, 2)
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.content), ["one", "the old way", "two", "the old way"])
        XCTAssertTrue(messages.allSatisfy { $0.failure == nil && !$0.isPartial })
        XCTAssertNil(model.lastError)
    }

    /// Any other refusal of the run is today's failure on the question.
    @MainActor
    func testARefusedRunIsAFailureOnTheQuestion() async throws {
        let hub = hub()
        hub.with { $0.start = .refused(.server(status: 429, code: RunCode.tooManyRuns, message: "busy")) }
        let (model, _) = try await Self.makeModel(behind: hub)
        try await XCTUnwrap(model.send("go")).value
        let question = try Self.last(model)
        XCTAssertEqual(question.role, .user)
        XCTAssertEqual(question.failure?.message, "busy")
        XCTAssertEqual(hub.with { $0.chats.count }, 0)
    }

    /// Stop cancels the run on the hub and keeps what arrived as a stopped
    /// reply; the background, on the same reply, cancels nothing.
    @MainActor
    func testStopCancelsTheRunAndTheBackgroundDoesNot() async throws {
        for backgrounds in [false, true] {
            let hub = hub()
            hub.with { $0.holdAt = 3 }
            let (model, _) = try await Self.makeModel(behind: hub)
            let task = try XCTUnwrap(model.send("go"))
            try await Self.until("three frames") { model.liveReply?.cursor == 3 }
            if backgrounds { await model.scene(.background).value } else { model.stop() }
            await task.value
            let id = try XCTUnwrap(hub.with { $0.starts.first?.id })
            let reply = try Self.last(model)
            XCTAssertTrue(reply.isPartial)
            XCTAssertNil(reply.failure)
            XCTAssertEqual(reply.content, "")
            XCTAssertEqual(reply.reasoning, "Keep it short.")
            if backgrounds {
                XCTAssertEqual(hub.with { $0.cancels }, [], "the background cancelled the run")
                XCTAssertEqual(reply.runID, id)
                XCTAssertEqual(reply.runCursor, 3)
            } else {
                XCTAssertEqual(hub.with { $0.cancels }, [id], "Stop did not cancel the run")
                XCTAssertNil(reply.runID, "a stopped reply still names its run")
            }
        }
    }

    /// Detached, a reply offers neither Continue nor Retry, the conversation
    /// takes no new question, and the row names the machine writing it.
    @MainActor
    func testAReplyStillBeingWrittenOffersNeitherContinueNorRetry() async throws {
        let hub = hub()
        hub.with { $0.holdAt = 2 }
        let (model, _) = try await Self.makeModel(behind: hub)
        _ = try XCTUnwrap(model.send("go"))
        try await Self.until("two frames") { model.liveReply?.cursor == 2 }
        await model.scene(.background).value

        let reply = try Self.last(model)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(reply.isPartial)
        XCTAssertNil(model.continueReply(), "Continue would start a second reply beside the running one")
        XCTAssertNil(model.retry(), "Retry would start a second reply beside the running one")
        XCTAssertNil(model.send("again"), "a new question went in under a reply still being written")
        XCTAssertEqual(
            model.writingLine(for: reply, in: conversation), "The reply is still being written on home.")
        XCTAssertNil(model.writingLine(for: conversation.messages[0], in: conversation))
        XCTAssertEqual(hub.with { $0.starts.count }, 1)
    }

    /// Deleting a conversation cancels the run still writing its reply, when
    /// its hub can be reached.
    @MainActor
    func testDeletingAConversationCancelsTheRunStillWritingItsReply() async throws {
        let hub = hub()
        hub.with { $0.dropAt = 0 }
        let (model, _) = try await Self.makeModel(behind: hub)
        try await XCTUnwrap(model.send("go")).value
        let reply = try Self.last(model)
        XCTAssertNotNil(reply.runID, "a drop with nothing read did not walk away from the run")
        model.deleteConversation(try XCTUnwrap(model.selectedConversationID))
        try await Self.until("the run to be cancelled") { hub.with { !$0.cancels.isEmpty } }
        XCTAssertEqual(hub.with { $0.cancels }, [reply.runID].compactMap { $0 })
    }
}
