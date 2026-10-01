import GGChatCore
import XCTest

@testable import GGChatUI

/// A turn whose answer was lost on the way may have started: it is kept and
/// put again under its id, and a list says whether it arrived or puts it
/// again. And a Stop
/// whose cancel is not answered yet has nothing read on beside it.
@MainActor
final class HubChatLostTurnTests: XCTestCase {
    private let question = "And how do I fix it?"
    private let quiet = HubChatSummary(id: 12, title: "Why the build broke", updatedAt: "2026-09-30 09:13:07")

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// Chat 12 open behind `hub`, with a turn sent whose answer was lost, and
    /// the pause before it is put again not yet over.
    private func lost(
        _ hub: FakeChatsHub, store: any Store, sleeper: ReadOnSleeper
    ) async throws -> (AppModel, ProviderConfig) {
        hub.with { $0.turnsLost = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store, sleeper: sleeper)
        model.sendToHubChat(question)
        try await until("the lost answer") { hub.with(\.turns).count == 1 && model.openHubReply?.reading == nil }
        try await until("the pause") { sleeper.pauses == [.seconds(2)] }
        return (model, config)
    }

    func testALostTurnIsKeptAndPutAgainUnderItsIDThenReadFromItsStart() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = 2 }
        let (model, config) = try await lost(hub, store: store, sleeper: ReadOnSleeper(immediate: false))
        let reply = try XCTUnwrap(model.openHubReply)
        XCTAssertTrue(model.openHubChatIsWriting, "a lost turn was not still being written")
        XCTAssertNil(model.openedHubChat?.notice, "a lost turn was said as a refusal")
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [], "a turn not answered was kept")
        XCTAssertEqual(hub.runs.with(\.reads).count, 0)

        await model.scene(.foreground).value
        try await until("the second answer") { hub.with(\.turns).count == 2 && model.openHubReply?.cursor == 2 }
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID, reply.runID])
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [HeldHubRun(runID: reply.runID, chatID: 12)])

        hub.runs.release()
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0])
        XCTAssertEqual(reply.content, "Pin the version.")
    }

    /// A list that does not name a lost turn's run does not end it: the Mac
    /// names a run only once it has reserved it, which may wait for a model
    /// to load. The reply is kept, still Writing, and put again under its
    /// id; here that answer is lost too, so nothing is read.
    func testALostTurnTheListDoesNotNameIsKept() async throws {
        let hub = FakeChatsHub([quiet])
        let (model, config) = try await lost(hub, store: InMemoryStore(), sleeper: ReadOnSleeper(immediate: false))
        let reply = try XCTUnwrap(model.openHubReply)
        hub.with { $0.turnsLost = 1 }
        await model.listHubChats(config.id)
        try await until("the second lost answer") { hub.with(\.turns).count == 2 && reply.reading == nil }
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID, reply.runID])
        XCTAssertTrue(model.hubReplies.contains { $0 === reply }, "a list forgot a turn that may be on its way")
        XCTAssertFalse(reply.ended)
        XCTAssertFalse(reply.started)
        XCTAssertEqual(model.mark(for: quiet, on: config.id), .writing)
        XCTAssertEqual(hub.with(\.opens), [12])
        XCTAssertEqual(hub.runs.with(\.reads).count, 0)
    }

    /// A turn that never reached the Mac is put again under its id when a
    /// list says the Mac answers and does not name its run, and is read.
    func testADroppedTurnIsPutAgainWhenAListDoesNotNameIt() async throws {
        let hub = FakeChatsHub([quiet])
        hub.runs.with { $0.holdAt = 2 }
        hub.with { $0.turnsDropped = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        try await until("the dropped turn") { hub.with(\.dropped).count == 1 && model.openHubReply?.reading == nil }
        let reply = try XCTUnwrap(model.openHubReply)
        XCTAssertEqual(hub.with(\.turns).count, 0)

        await model.listHubChats(config.id)
        try await until("the turn put again") { hub.with(\.turns).count == 1 && reply.cursor == 2 }
        XCTAssertEqual(hub.with(\.dropped), [reply.runID])
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID])
        hub.runs.release()
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(reply.content, "Pin the version.")
    }

    /// A dropped turn in a chat no longer on screen is put again under its
    /// id on coming back, without a list and without opening it.
    func testADroppedTurnInAChatNotOnScreenIsPutAgainOnComingBack() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.turnsDropped = 1 }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        try await until("the dropped turn") { hub.with(\.dropped).count == 1 && model.openHubReply?.reading == nil }
        let reply = try XCTUnwrap(model.openHubReply)
        model.selection = nil
        XCTAssertTrue(model.hubReplies.contains { $0 === reply })
        let lists = hub.with(\.lists)

        await model.scene(.foreground).value
        try await until("the turn put again") { hub.with(\.turns).count == 1 }
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID])
        XCTAssertEqual(hub.with(\.lists), lists, "a list put it again, not coming back")
        XCTAssertNil(model.openedHubChat)
        try await until("the end") { model.hubReplies.isEmpty }
    }

    /// A reply whose turn started is never put again: a list that names its
    /// run keeps it, and coming back with its chat not on screen sends nothing.
    func testAStartedReplyIsNotPutAgain() async throws {
        let hub = FakeChatsHub([quiet])
        hub.runs.with { $0.holdAt = 2 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        try await until("two frames") { model.openHubReply?.cursor == 2 }
        let reply = try XCTUnwrap(model.openHubReply)
        model.selection = nil
        try await until("walked away") { reply.reading == nil }

        let named = HubChatSummary(id: 12, title: quiet.title, updatedAt: quiet.updatedAt, liveRun: reply.runID)
        hub.with { $0.list = .success(HubChatList(chats: [named])) }
        await model.listHubChats(config.id)
        await model.scene(.foreground).value
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID])
        XCTAssertTrue(reply.started)
        XCTAssertTrue(model.hubReplies.contains { $0 === reply })
    }

    /// A lost turn put again is answered with its run, already ended: the
    /// reply is read to its end and the Mac's rows are read in its place.
    func testALostTurnPutAgainAfterItsRunEndedIsReadThenItsRows() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        let (model, config) = try await lost(hub, store: store, sleeper: ReadOnSleeper(immediate: false))
        let reply = try XCTUnwrap(model.openHubReply)
        hub.with { state in
            state.turnStatus = .completed
            state.chats[12] = FakeChatsHub.saved(question, "Pin the version.")
        }
        await model.scene(.foreground).value
        try await until("the rows") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID, reply.runID])
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0])
        XCTAssertEqual(reply.content, "Pin the version.")
        XCTAssertEqual(HubChatContinueTests.shown(model).suffix(2), [question, "Pin the version."])
        XCTAssertNil(model.openedHubChat?.notice)
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [])
    }

    /// A list that names a lost turn's run as live says it arrived: it is
    /// kept, now as started, on the provider's row too.
    func testALostTurnTheListNamesIsKeptAsStarted() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub([quiet])
        let (model, config) = try await lost(hub, store: store, sleeper: ReadOnSleeper(immediate: false))
        let reply = try XCTUnwrap(model.openHubReply)
        let named = HubChatSummary(id: 12, title: quiet.title, updatedAt: quiet.updatedAt, liveRun: reply.runID)
        hub.with { $0.list = .success(HubChatList(chats: [named])) }
        await model.listHubChats(config.id)
        XCTAssertTrue(reply.started)
        XCTAssertTrue(model.hubReplies.contains { $0 === reply })
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [HeldHubRun(runID: reply.runID, chatID: 12)])
        XCTAssertEqual(model.mark(for: named, on: config.id), .writing)
    }

    /// Between Stop and the Mac's answer to its cancel, a read-on reads
    /// nothing beside it: the one reading after the cancel is Stop's own.
    func testNothingReadsOnBesideAStopWhoseCancelIsNotAnsweredYet() async throws {
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = 2 }
        hub.with { $0.holdsCancels = true }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        try await until("two frames") { model.openHubReply?.cursor == 2 }

        model.stopHubReply()
        try await until("the cancel asked") { hub.with(\.cancelsAsked) == 1 }
        model.readOnHubReply()
        await model.scene(.foreground).value
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(hub.runs.with(\.reads).count, 1, "a read-on started beside the Stop")

        hub.with { $0.holdsCancels = false }
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0, 2])
    }
}
