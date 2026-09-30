import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A Mac's chat carried on from this phone: a send puts the new text alone,
/// the reply is read from the Mac's run into memory, Stop cancels it, and
/// the Mac's rows are read in its place once it ends. Nothing is written to
/// the phone's store.
@MainActor
final class HubChatContinueTests: XCTestCase {
    private let question = "And how do I fix it?"

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// A model behind `hub` with chat 12 open and its rows read.
    static func opened(
        _ hub: FakeChatsHub, store: any Store = InMemoryStore(), sleeper: any Sleeper = ReadOnSleeper(immediate: false)
    ) async throws -> (AppModel, ProviderConfig) {
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub, store: store, sleeper: sleeper)
        try await AppModelRunTests.until("the list") { model.hubChats[config.id] != nil && model.hubListing.isEmpty }
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await AppModelRunTests.until("the rows") { model.openedHubChat?.state.showsRows == true }
        return (model, config)
    }

    private func counts(_ store: SwiftDataStore) throws -> [Int] {
        [
            try store.context.fetchCount(FetchDescriptor<ConversationRecord>()),
            try store.context.fetchCount(FetchDescriptor<MessageRecord>()),
        ]
    }

    static func shown(_ model: AppModel) -> [String] {
        guard case .read(let rows)? = model.openedHubChat?.state else { return [] }
        return rows.map(\.content)
    }

    func testASendPutsOnlyTheNewTextAndTheReplyIsReadThenReplacedByTheMacsRows() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = UInt32(FakeChatsHub.reply.count) }
        let (model, _) = try await Self.opened(hub, store: store)
        let before = try counts(store)

        model.sendToHubChat("  \(question)\n")
        try await until("the reply") { model.openHubReply?.content == "Pin the version." }
        let reply = try XCTUnwrap(model.openHubReply)
        XCTAssertEqual(reply.reasoning, "It moved.")
        XCTAssertEqual(reply.tools, ["Read File: Cargo.lock"])
        XCTAssertEqual(reply.question, question)
        XCTAssertTrue(model.openHubChatIsWriting)
        XCTAssertNotNil(UUID(uuidString: reply.runID), "the run id was not minted here")
        let turns = hub.with(\.turns)
        XCTAssertEqual(turns.map(\.turn), [HubTurn(conversationID: 12, content: question)])
        XCTAssertEqual(turns.map(\.runID), [reply.runID])
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0])
        XCTAssertEqual(try counts(store), before, "the send wrote to the store")

        hub.with { $0.chats[12] = FakeChatsHub.saved(question, "Pin the version.") }
        hub.runs.release()
        try await until("the Mac's rows") { model.hubReplies.isEmpty }
        XCTAssertEqual(Self.shown(model).suffix(2), [question, "Pin the version."])
        XCTAssertEqual(hub.with(\.opens), [12, 12])
        XCTAssertFalse(model.openHubChatIsWriting)
        XCTAssertNil(model.openedHubChat?.notice)
        XCTAssertEqual(try counts(store), before, "the end wrote to the store")
        XCTAssertEqual(model.conversations.count, 1)
        XCTAssertEqual(hub.runs.with(\.cancels), [])
    }

    /// Stop cancels the run on the Mac, reads on from where the reply was to
    /// the run's end, and then reads the rows the Mac saved.
    func testStopCancelsTheRunAndTheRowsAreReadOnceItEnds() async throws {
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = 2 }
        let (model, _) = try await Self.opened(hub)
        model.sendToHubChat(question)
        try await until("two frames") { model.openHubReply?.cursor == 2 }
        XCTAssertEqual(model.openHubReply?.reasoning, "It ")
        let runID = try XCTUnwrap(model.openHubReply?.runID)

        model.stopHubReply()
        try await until("the rows") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.runs.with(\.cancels), [runID])
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0, 2])
        XCTAssertEqual(hub.with(\.opens), [12, 12])
    }

    /// Each way the Mac refuses a turn is said in the view, in its own words,
    /// and nothing is read or kept.
    func testEachRefusalIsSaidInTheViewAndKeepsNothing() async throws {
        let hub = FakeChatsHub()
        let (model, _) = try await Self.opened(hub)
        let busy = ProviderError.server(status: 429, code: "agent_busy", message: "all agent loop slots are in use")
        let cases: [(HubTurnFailure, String)] = [
            (.noModel, "This chat has no model; pick one on home."),
            (.replyInProgress, "A reply is already being written on home."),
            (.chatGone, "home no longer has this chat."),
            (.refused(busy), "home did not take this message. all agent loop slots are in use"),
        ]
        for (failure, line) in cases {
            hub.with { $0.turnFailure = failure }
            await model.sendToHubChat(question)?.value
            XCTAssertEqual(model.openedHubChat?.notice, line, "\(failure)")
            XCTAssertEqual(model.hubReplies.count, 0, "\(failure)")
        }
        XCTAssertEqual(hub.runs.with(\.reads).count, 0)
        XCTAssertEqual(hub.with(\.turns).count, cases.count)
    }

    /// While the Mac writes a reply the phone sent for, a second send is
    /// refused here, in the words the Mac would use.
    func testASecondSendWhileTheMacWritesIsRefusedHere() async throws {
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = 1 }
        let (model, _) = try await Self.opened(hub)
        model.sendToHubChat(question)
        try await until("the first frame") { model.openHubReply?.tools.isEmpty == false }
        XCTAssertNil(model.sendToHubChat("And again?"))
        XCTAssertEqual(model.openedHubChat?.notice, "A reply is already being written on home.")
        XCTAssertEqual(hub.with(\.turns).count, 1)
        hub.runs.release()
    }

    /// A run that fails says so, with the Mac's sentence, and the rows the
    /// Mac saved are read in its place.
    func testAFailedRunSaysSoAndTheRowsAreReadAgain() async throws {
        let hub = FakeChatsHub()
        hub.runs.with { state in
            state.ending = .failed
            state.error = RunError(code: "upstream_error", message: "the model stopped answering")
        }
        let (model, _) = try await Self.opened(hub)
        model.sendToHubChat(question)
        try await until("the rows") { model.hubReplies.isEmpty }
        XCTAssertEqual(model.openedHubChat?.notice, "The reply stopped on home: the model stopped answering")
        XCTAssertEqual(hub.with(\.opens), [12, 12])
    }
}
