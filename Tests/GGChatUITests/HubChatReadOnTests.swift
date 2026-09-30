import GGChatCore
import XCTest

@testable import GGChatUI

/// Walking away from a reply a Mac is writing to its chat, and reading on:
/// leaving the chat and the background walk away and cancel nothing, a
/// return reads on from the cursor with nothing applied twice, a reading
/// that gets nothing is paced, and a run the Mac no longer has, or a removed
/// provider, is forgotten.
@MainActor
final class HubChatReadOnTests: XCTestCase {
    private let question = "And how do I fix it?"

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    private struct Writing {
        let model: AppModel
        let config: ProviderConfig
        let reply: HubLiveReply
    }

    /// Chat 12 open behind `hub`, with a reply sent and read to its second
    /// frame, where the run holds.
    private func writing(_ hub: FakeChatsHub, store: any Store = InMemoryStore()) async throws -> Writing {
        hub.runs.with { $0.holdAt = 2 }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        model.sendToHubChat(question)
        try await until("two frames") { model.openHubReply?.cursor == 2 }
        return Writing(model: model, config: config, reply: try XCTUnwrap(model.openHubReply))
    }

    func testLeavingTheChatWalksAwayAndOpeningItAgainReadsOnFromTheCursor() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        let run = try await writing(hub, store: store)
        let (model, config, reply) = (run.model, run.config, run.reply)
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [HeldHubRun(runID: reply.runID, chatID: 12)])

        model.selection = nil
        try await until("the walk away") { reply.reading == nil }
        XCTAssertEqual(hub.runs.with(\.cancels), [], "leaving the chat cancelled the run")
        XCTAssertTrue(model.hubReplies.contains { $0 === reply }, "the reply was not kept")

        // The Mac sends every event again: none may be applied twice.
        hub.runs.with { state in
            state.holdAt = nil
            state.ignoresAfter = true
        }
        hub.with { $0.chats[12] = FakeChatsHub.saved(question, "Pin the version.") }
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0, 2])
        XCTAssertEqual(reply.reasoning, "It moved.")
        XCTAssertEqual(reply.content, "Pin the version.")
        XCTAssertEqual(reply.tools, ["Read File: Cargo.lock"])
        XCTAssertEqual(HubChatContinueTests.shown(model).suffix(2), [question, "Pin the version."])
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [], "an ended run was kept")
    }

    func testTheBackgroundWalksAwayAndComingBackReadsOn() async throws {
        let hub = FakeChatsHub()
        let run = try await writing(hub)
        let (model, reply) = (run.model, run.reply)
        await model.scene(.background).value
        XCTAssertNil(reply.reading)
        XCTAssertEqual(hub.runs.with(\.cancels), [])

        hub.runs.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0, 2])
        XCTAssertEqual(reply.content, "Pin the version.")
    }

    /// A reading that gets nothing reads on after each of the pauses this
    /// device's own replies wait, then waits for a return; the reply is
    /// still being written, and Stop is still there.
    func testAReadingThatGetsNothingReadsOnAfterEachPauseThenWaits() async throws {
        let sleeper = ReadOnSleeper(immediate: true)
        let hub = FakeChatsHub()
        hub.runs.with { $0.readAnswer = .dropped(.transport("the Mac is away")) }
        let (model, _) = try await HubChatContinueTests.opened(hub, sleeper: sleeper)
        model.sendToHubChat(question)
        try await until("the pauses") { sleeper.pauses.count == 3 && hub.runs.with(\.reads).count == 4 }
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(sleeper.pauses, AppModel.readOnDelays)
        XCTAssertEqual(hub.runs.with(\.reads).count, 4, "it read on after the last pause")
        XCTAssertTrue(model.openHubChatIsWriting)
    }

    /// A run the Mac no longer has is over: the rows are read, and it is
    /// forgotten.
    func testARunTheMacNoLongerHasReadsTheRowsAndIsForgotten() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        let run = try await writing(hub, store: store)
        let (model, config, reply) = (run.model, run.config, run.reply)
        model.selection = nil
        try await until("the walk away") { reply.reading == nil }
        hub.runs.with { $0.forgotten = true }
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.with(\.opens), [12, 12, 12])
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [])
    }

    /// Removing the provider forgets its replies, and cancels nothing: they
    /// are the Mac's.
    func testRemovingTheProviderForgetsItsRepliesAndCancelsNothing() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        let run = try await writing(hub, store: store)
        let (model, config) = (run.model, run.config)
        model.removeProvider(config.id)
        XCTAssertEqual(model.hubReplies.count, 0)
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [])
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(hub.runs.with(\.cancels), [])
    }

    /// A Mac's chat says Writing while this phone holds a reply the Mac is
    /// writing to it, though the Mac's list does not say so and the Mac is
    /// out of reach, and nothing once it has ended. Never New.
    func testAMacChatSaysWritingWhileThePhoneHoldsItsReply() async throws {
        let quiet = HubChatSummary(id: 12, title: "Why the build broke", updatedAt: "2026-09-30 09:13:07")
        let hub = FakeChatsHub([quiet])
        let run = try await writing(hub)
        let (model, config) = (run.model, run.config)
        XCTAssertEqual(model.mark(for: quiet, on: config.id), .writing)
        model.selection = nil
        try await until("the walk away") { run.reply.reading == nil }
        await model.disconnectPipe(for: config.id, leaving: .closed)
        XCTAssertEqual(model.mark(for: quiet, on: config.id), .writing, "a reply held here lost its mark")

        hub.runs.with { $0.holdAt = nil }
        await model.connectPipe(for: config)
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertNil(model.mark(for: quiet, on: config.id))
    }
}
