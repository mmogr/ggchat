import GGChatCore
import XCTest

@testable import GGChatUI

/// When a change to a Mac's chat is not sent, or its answer not shown
/// (ADR 0010): while a reply is being written or another change is on its
/// way, and when the Mac is out of reach, the view says why; a change
/// answered after its chat was left opens and answers nothing; a change
/// made in place reads the chat again; and an editor open across a read
/// still names its row.
@MainActor
final class HubChatBranchGuardsTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private typealias Branching = HubChatBranchingTests

    func testAChangeWhileAReplyIsWrittenOrAChangeIsOnItsWayIsRefused() async throws {
        let hub = Branching.hub(HubChatChanged(conversationID: 13, forked: true, answer: false))
        hub.with { $0.holdsChanges = true }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        let reply = try Branching.row("A dependency moved.", model)

        let first = try XCTUnwrap(model.regenerateHubMessage(reply))
        XCTAssertNil(model.branchHubChat(from: reply), "a second change went out beside the first")
        XCTAssertEqual(model.openedHubChat?.notice, "A reply is already being written on home.")
        XCTAssertNil(model.sendToHubChat("And now?"), "a send went out beside a change")
        try await Runs.until("the change") { hub.with(\.changes).count == 1 }
        hub.with { $0.holdsChanges = false }
        await first.value
        XCTAssertEqual(hub.with(\.changes).count, 1)

        model.openHubBranch(12)
        try await Runs.until("chat 12") { model.openedHubChat?.state.showsRows == true }
        model.hubReplies.append(
            HubLiveReply(providerID: model.openedHubChat!.providerID, chatID: 12, runID: "r", question: "q"))
        XCTAssertNil(model.regenerateHubMessage(try Branching.row("A dependency moved.", model)))
        XCTAssertEqual(model.openedHubChat?.notice, "A reply is already being written on home.")
        XCTAssertEqual(hub.with(\.changes).count, 1)
    }

    func testAChangeToAMacOutOfReachIsRefused() async throws {
        let hub = Branching.hub(HubChatChanged(conversationID: 13, forked: true, answer: false))
        let (model, config) = try await HubChatContinueTests.opened(hub)
        await model.disconnectPipe(for: config.id, leaving: .closed)

        XCTAssertNil(model.branchHubChat(from: try Branching.row("A dependency moved.", model)))
        XCTAssertEqual(model.openedHubChat?.notice, "home is unreachable.")
        XCTAssertEqual(hub.with(\.changes).count, 0)
    }

    /// The Mac's answer to a change whose chat was left meanwhile neither
    /// opens its branch, answers it, nor says anything on the chat open now.
    func testAChangeAnsweredAfterItsChatWasLeftOpensNothing() async throws {
        let hub = Branching.hub(HubChatChanged(conversationID: 13, forked: true, answer: true))
        hub.with { $0.holdsChanges = true }
        let (model, config) = try await HubChatContinueTests.opened(hub)

        let made = try XCTUnwrap(model.regenerateHubMessage(try Branching.row("A dependency moved.", model)))
        try await Runs.until("the change") { hub.with(\.changes).count == 1 }
        model.selection = .hub(providerID: config.id, chatID: 9)
        hub.with { $0.holdsChanges = false }
        await made.value
        XCTAssertEqual(model.selection, .hub(providerID: config.id, chatID: 9))
        XCTAssertEqual(hub.with(\.turns).count, 0, "a chat no longer open was answered")

        model.selection = .hub(providerID: config.id, chatID: 12)
        try await Runs.until("chat 12") { model.openedHubChat?.state.showsRows == true }
        hub.with {
            $0.holdsChanges = true
            $0.changeAnswer = .failure(.refused(.server(status: 400, code: "not_a_reply", message: "no")))
        }
        let refused = try XCTUnwrap(model.regenerateHubMessage(try Branching.row("A dependency moved.", model)))
        try await Runs.until("the change") { hub.with(\.changes).count == 2 }
        model.selection = .hub(providerID: config.id, chatID: 9)
        hub.with { $0.holdsChanges = false }
        await refused.value
        XCTAssertNil(model.openedHubChat?.notice, "a refusal was said on another chat")
    }

    /// A change the Mac makes in place leaves the chat open: its rows are
    /// read again, and its question answered.
    func testAChangeMadeInPlaceReadsTheChatAgainAndAnswersIt() async throws {
        let hub = Branching.hub(HubChatChanged(conversationID: 12, forked: false, answer: true))
        let (model, config) = try await HubChatContinueTests.opened(hub)
        hub.with { $0.chats[12] = Branching.branch }

        await model.editHubMessage(try Branching.row("Why did the build break?", model), to: "Why did it break?")?.value

        XCTAssertEqual(model.selection, .hub(providerID: config.id, chatID: 12))
        try await Runs.until("the chat read again") { HubChatContinueTests.shown(model) == ["Why did it break?"] }
        XCTAssertEqual(hub.with(\.turns).map(\.turn), [HubTurn(conversationID: 12, content: "", answerSaved: true)])

        // With nothing to answer, only the read shows the change.
        try await Runs.until("the answer's rows") { model.hubReplies.isEmpty }
        hub.with {
            $0.changeAnswer = .success(HubChatChanged(conversationID: 12, forked: false, answer: false))
            $0.chats[12] = FakeChatsHub.opened
        }
        await model.branchHubChat(from: try Branching.row("Why did it break?", model))?.value
        try await Runs.until("the chat read again") { HubChatContinueTests.shown(model).count == 2 }
        XCTAssertEqual(hub.with(\.turns).count, 1)
    }

    /// The chat read again while the editor is open keeps its rows' ids, so
    /// the edit still names the row it was opened on.
    func testAnEditorOpenAcrossAReadStillNamesItsRow() async throws {
        let hub = Branching.hub(HubChatChanged(conversationID: 13, forked: true, answer: false))
        let (model, config) = try await HubChatContinueTests.opened(hub)
        let question = try Branching.row("Why did the build break?", model)

        hub.with { $0.opens.removeAll() }
        model.hubPipeCameUp(config.id)
        try await Runs.until("the chat read again") { hub.with(\.opens) == [12] && model.hubReading == nil }

        await model.editHubMessage(question, to: "Why did it break?")?.value
        XCTAssertEqual(
            hub.with(\.changes).map(\.change),
            [HubChatChange(.edit(messageID: 40, content: "Why did it break?", images: []))])
    }
}
