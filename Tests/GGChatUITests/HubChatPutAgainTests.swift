import GGChatCore
import XCTest

@testable import GGChatUI

/// When a send whose `PUT` was never answered is put again, and when it is
/// not: never beside one being put, never while its Mac is out of reach or
/// the app is going away, never once Stop ended it or a refusal took it. A
/// refusal while its chat is not on screen gives its text back on opening.
@MainActor
final class HubChatPutAgainTests: XCTestCase {
    private let question = "And how do I fix it?"
    private let quiet = HubChatSummary(id: 12, title: "Why the build broke", updatedAt: "2026-09-30 09:13:07")

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// Chat 12 open behind `hub`, with a send that never reached the Mac,
    /// and the pause before it is put again not yet over.
    private func dropped(_ hub: FakeChatsHub) async throws -> (AppModel, ProviderConfig) {
        hub.with { $0.turnsDropped = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        try await until("the dropped send") { hub.with(\.dropped).count == 1 && model.openHubReply?.reading == nil }
        return (model, config)
    }

    /// A refusal while a list is on its way takes the send: the list that
    /// then does not name its run puts nothing.
    func testARefusedSendIsNotPutAgainByAListOnItsWay() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await dropped(hub)
        let reply = try XCTUnwrap(model.openHubReply)
        model.selection = nil
        hub.with { $0.holdsLists = true }
        let listing = Task { await model.listHubChats(config.id) }
        try await until("the list asked") { !model.hubListing.isEmpty }
        hub.with { $0.turnFailure = .replyInProgress }
        await model.scene(.foreground).value
        try await until("the refusal") { model.hubReplies.isEmpty && reply.reading == nil }
        XCTAssertEqual(hub.with(\.turns).count, 1)

        hub.with { state in
            state.turnFailure = nil
            state.holdsLists = false
        }
        await listing.value
        await settle()
        XCTAssertEqual(hub.with(\.turns).count, 1, "a refused send was put again")
        XCTAssertFalse(reply.started)
        XCTAssertTrue(model.hubReplies.isEmpty)
    }

    /// A send whose `PUT` is under way is not put beside it.
    func testASendBeingPutIsNotPutBesideItself() async throws {
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = 2 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        model.hubPipeCameUp(config.id)
        try await until("two frames") { model.openHubReply?.cursor == 2 }
        await settle()
        XCTAssertEqual(hub.with(\.turns).count, 1)
        hub.runs.release()
        try await until("the end") { model.hubReplies.isEmpty }
    }

    /// Opening another chat while the Mac is out of reach puts nothing.
    func testADroppedSendIsNotPutWhileItsMacIsOutOfReach() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await dropped(hub)
        model.setPipeStatus(.idle, for: config.id)
        model.selection = .hub(providerID: config.id, chatID: 9)
        await settle()
        XCTAssertEqual(hub.with(\.turns).count, 0)
    }

    /// Stop while the Mac is out of reach ends the send here; the pipe
    /// coming back does not put it.
    func testAStoppedSendIsNotPutWhenThePipeComesBack() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await dropped(hub)
        let reply = try XCTUnwrap(model.openHubReply)
        let up = model.pipeStatus(for: config.id)
        model.setPipeStatus(.idle, for: config.id)
        model.stopHubReply()
        XCTAssertTrue(reply.ended)
        model.setPipeStatus(up, for: config.id)
        await settle()
        XCTAssertEqual(hub.with(\.turns).count, 0, "a stopped send was put")
    }

    /// On the way to the background, the pipe coming up puts nothing.
    func testNothingIsPutOnTheWayToTheBackground() async throws {
        let hub = FakeChatsHub([quiet])
        let (model, config) = try await dropped(hub)
        model.isAway = true
        model.hubPipeCameUp(config.id)
        await settle()
        XCTAssertEqual(hub.with(\.turns).count, 0)
    }

    /// The pipe coming up puts a dropped send again at once, before the list
    /// it also asks for answers.
    func testADroppedSendIsPutAgainWhenThePipeComesUp() async throws {
        let hub = FakeChatsHub([quiet])
        hub.runs.with { $0.holdAt = 2 }
        let (model, config) = try await dropped(hub)
        let reply = try XCTUnwrap(model.openHubReply)
        let up = model.pipeStatus(for: config.id)
        model.setPipeStatus(.idle, for: config.id)
        hub.with { $0.holdsLists = true }
        model.setPipeStatus(up, for: config.id)
        try await until("the send put again") { hub.with(\.turns).count == 1 }
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID])
        XCTAssertFalse(model.hubListing.isEmpty, "the list answered first")
        hub.with { $0.holdsLists = false }
        hub.runs.release()
        try await until("the end") { model.hubReplies.isEmpty }
    }

    /// Leaving the chat cuts its send short: it is sent again at once under
    /// its id, and its reply read off screen to its end.
    func testASendCutShortByLeavingItsChatIsSentAgainAndReadToItsEnd() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.turnsHeldUntilCancelled = 1 }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat(question)
        let reply = try XCTUnwrap(model.openHubReply)
        model.selection = nil
        try await until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.with(\.dropped), [reply.runID])
        XCTAssertEqual(hub.with { $0.turns.map(\.runID) }, [reply.runID])
        XCTAssertEqual(reply.content, "Pin the version.")
        XCTAssertNil(model.openedHubChat)
    }

    /// A send refused while its chat is not on screen gives its text back,
    /// with why, when the chat is next opened, and only then.
    func testARefusedSendOffScreenGivesItsTextBackOnOpening() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await dropped(hub)
        model.selection = nil
        hub.with { $0.turnFailure = .replyInProgress }
        await model.scene(.foreground).value
        try await until("the refusal") { model.hubReplies.isEmpty }

        model.selection = .hub(providerID: config.id, chatID: 12)
        XCTAssertEqual(model.openedHubChat?.notice, AppModel.busyLine(config))
        XCTAssertEqual(model.takeUnsentHubText(), question)
        model.selection = nil
        model.selection = .hub(providerID: config.id, chatID: 12)
        XCTAssertNil(model.openedHubChat?.unsent)
        XCTAssertNil(model.openedHubChat?.notice)
    }
}
