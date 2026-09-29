import GGChatCore
import XCTest

@testable import GGChatUI

/// Coming back to a reply the hub went on writing: it is read on from the
/// stored cursor, nothing twice and nothing skipped, and ends as the run did.
final class AppModelRunCatchUpTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    /// Sends, lets `frames` of the reply arrive, and goes to the background.
    @MainActor
    private func detach(after frames: UInt32, from hub: FakeRunHub) async throws -> (AppModel, ProviderConfig) {
        hub.with { $0.holdAt = frames }
        let (model, config) = try await Runs.makeModel(behind: hub)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("the run to be read") { hub.with { !$0.reads.isEmpty } }
        try await Runs.until("\(frames) frames") { model.liveReply?.cursor == frames }
        await model.scene(.background).value
        await task.value
        return (model, config)
    }

    /// Comes back with the hub no longer holding, and waits for the reply.
    @MainActor
    private func comeBack(_ model: AppModel, to hub: FakeRunHub) async throws {
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply to be read on") {
            model.liveReply == nil && model.selectedConversation?.messages.contains(where: \.isBeingWritten) == false
        }
    }

    /// The background keeps what arrived with the run's id and cursor, before
    /// the first token too, and coming back reads on after that cursor to the
    /// whole reply, under one run.
    @MainActor
    func testTheBackgroundKeepsTheRunAndComingBackReadsOnFromItsCursor() async throws {
        for cut: UInt32 in [0, 5] {
            let hub = hub()
            let (model, _) = try await detach(after: cut, from: hub)
            let kept = try XCTUnwrap(model.store.loadConversations().first?.messages.last)
            XCTAssertEqual(kept.role, .assistant, "nothing was kept for the return to read on into")
            XCTAssertEqual(kept.runID, hub.with { $0.starts.first?.id })
            XCTAssertEqual(kept.runCursor, cut)
            try await comeBack(model, to: hub)
            let reply = try Runs.last(model)
            XCTAssertEqual(reply.content, Runs.text)
            XCTAssertEqual(reply.reasoning, Runs.reasoning)
            XCTAssertFalse(reply.isPartial)
            XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, cut])
            XCTAssertEqual(hub.with { $0.starts.count }, 1, "coming back started a second run")
        }
    }

    /// A background while the reply is being read on walks away again, with
    /// the cursor moved on and nothing read twice; an empty reply is kept as
    /// the placeholder it was.
    @MainActor
    func testABackgroundWhileReadingOnKeepsTheRunAgain() async throws {
        for (first, second): (UInt32, UInt32) in [(0, 0), (2, 5)] {
            let hub = hub()
            let (model, _) = try await detach(after: first, from: hub)
            hub.with { $0.holdAt = second }
            await model.scene(.foreground).value
            try await Runs.until("the reply to be read on") { hub.with { $0.reads.count } == 2 }
            try await Runs.until("\(second) frames") { model.liveReply?.cursor == second }
            await model.scene(.background).value
            let kept = try Runs.last(model)
            XCTAssertEqual(kept.role, .assistant, "the reply walked away from was not kept")
            XCTAssertNotNil(kept.runID)
            XCTAssertEqual(kept.runCursor, second)
            XCTAssertEqual(kept.reasoning, second == 0 ? nil : "Keep it short.")
            XCTAssertEqual(kept.content, second == 0 ? "" : "It reads ")
            try await comeBack(model, to: hub)
            XCTAssertEqual(try Runs.last(model).content, Runs.text)
            XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, first, second])
        }
    }

    /// A reply read on to its end is as the run ended: failed shows the
    /// run's failure, cancelled is a stopped reply, and one the hub no
    /// longer has keeps what arrived, with Continue and a sentence saying so.
    @MainActor
    func testAReplyReadOnEndsAsTheRunDid() async throws {
        let failed = hub()
        failed.with { $0.ending = .failed }
        failed.with { $0.error = RunError(code: "model_unavailable", message: "The model could not be loaded.") }
        var (model, _) = try await detach(after: 5, from: failed)
        try await comeBack(model, to: failed)
        var reply = try Runs.last(model)
        XCTAssertTrue(reply.isPartial)
        XCTAssertEqual(reply.failure?.message, "The reply stopped: The model could not be loaded.")
        XCTAssertEqual(reply.failure?.code, "model_unavailable")

        let cancelled = hub()
        cancelled.with { $0.ending = .cancelled }
        (model, _) = try await detach(after: 5, from: cancelled)
        try await comeBack(model, to: cancelled)
        reply = try Runs.last(model)
        XCTAssertTrue(reply.isPartial)
        XCTAssertNil(reply.failure)

        let forgotten = hub()
        (model, _) = try await detach(after: 5, from: forgotten)
        forgotten.with { $0.forgotten = true }
        try await comeBack(model, to: forgotten)
        reply = try Runs.last(model)
        XCTAssertTrue(reply.isPartial)
        XCTAssertEqual(reply.content, "It reads ")
        XCTAssertEqual(reply.failure?.message, "home no longer has the rest of this reply.")
        XCTAssertNotNil(model.continueReply(), "a reply the hub lost offers no Continue")
    }

    /// A placeholder the hub no longer has is not kept as a reply: the
    /// question gets the sentence, and Retry.
    @MainActor
    func testAnEmptyReplyTheHubNoLongerHasLeavesTheQuestionWithRetry() async throws {
        let hub = hub()
        let (model, _) = try await detach(after: 0, from: hub)
        hub.with { $0.forgotten = true }
        try await comeBack(model, to: hub)
        let question = try Runs.last(model)
        XCTAssertEqual(question.role, .user)
        XCTAssertEqual(question.failure?.message, "home no longer has the rest of this reply.")
        XCTAssertNotNil(model.retry())
    }

    /// A connection that drops while the app is in front is not a failure
    /// and never a second run: the reply walks away and reads on at once.
    @MainActor
    func testADropInFrontReadsOnInsteadOfFailing() async throws {
        let hub = hub()
        hub.with { $0.dropAt = 4 }
        let (model, _) = try await Runs.makeModel(behind: hub)
        try await XCTUnwrap(model.send("go")).value
        try await Runs.until("the reply to be read on") { model.liveReply == nil && hub.with { $0.reads.count } == 2 }
        let reply = try Runs.last(model)
        XCTAssertEqual(reply.content, Runs.text)
        XCTAssertNil(reply.failure)
        XCTAssertFalse(reply.isPartial)
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 4])
        XCTAssertEqual(hub.with { $0.starts.count }, 1)
    }

    /// A launch reads on a reply kept by an earlier one, once its pipe is up.
    @MainActor
    func testALaunchReadsOnAReplyTheLastOneWalkedAwayFrom() async throws {
        let hub = hub()
        let store = InMemoryStore()
        let secrets = InMemorySecrets()
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(Runs.ticket)), defaultModel: "mock-27b")
        try store.save(provider: config)
        try secrets.setSecret(Runs.ticket, .ticket, for: config.id)
        try secrets.setSecret("secret-token", .token, for: config.id)
        let conversation = Conversation(
            providerID: config.id,
            messages: [
                Message(role: .user, content: "go", createdAt: .distantPast),
                Message(
                    role: .assistant, content: "", isPartial: true, createdAt: .distantPast, runID: "r", runCursor: 3),
            ], createdAt: .distantPast, updatedAt: .distantPast)
        try store.save(conversation: conversation)
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: store, secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: hub, registry: registry),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "launch.\(UUID().uuidString)")!))

        model.load()

        try await Runs.until("the reply to be read on") {
            model.liveReply == nil && model.selectedConversation?.messages.last?.runID == nil
        }
        let reply = try Runs.last(model)
        XCTAssertEqual(reply.content, Runs.text)
        XCTAssertNil(reply.reasoning, "the three reasoning frames were read again")
        XCTAssertFalse(reply.isPartial)
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [3])
    }

    /// Cut after every frame of the reply in turn, walked away from and read
    /// on, the reply is the same as one read unbroken; so it is when the hub
    /// sends every frame again from the first.
    @MainActor
    func testEveryCutOfTheReplyReadsOnToTheSameText() async throws {
        let count = UInt32(FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning).count)
        for replays in [false, true] {
            for cut in 0...count {
                let hub = hub()
                hub.with { $0.ignoresAfter = replays }
                let (model, _) = try await detach(after: cut, from: hub)
                XCTAssertEqual(try Runs.last(model).runCursor, cut)
                try await comeBack(model, to: hub)
                let reply = try Runs.last(model)
                XCTAssertEqual(reply.content, Runs.text, "cut after \(cut), replayed: \(replays)")
                XCTAssertEqual(reply.reasoning, Runs.reasoning, "cut after \(cut), replayed: \(replays)")
                let stored = try XCTUnwrap(model.store.loadConversations().first?.messages.last)
                XCTAssertEqual(stored.content, Runs.text)
            }
        }
    }
}
