import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The Thinking switch of a Mac's chat. The Mac remembers the choice: an
/// opened chat shows what it remembers, the turn that changes it says so
/// once, as `off` or `default`, a turn put again says the same, and nothing
/// of it is written to this phone (ADR 0007, ADR 0009).
@MainActor
final class HubChatThinkingTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private let question = "And how do I fix it?"
    /// A Mac's models: the one chat 12 names thinks, and one does not.
    static let models = [ModelInfo(id: "qwen3-8b", capabilities: ["reasoning"]), ModelInfo(id: "plain-4b")]

    /// A Mac that lists chat 12's model as one that thinks, and remembers
    /// `thinking` for the chat. As gglib does, it remembers what a turn it
    /// takes says (`FakeChatsHub.startTurn`).
    static func hub(remembering thinking: HubThinking? = nil) -> FakeChatsHub {
        let hub = FakeChatsHub()
        hub.with { state in
            state.models = models
            state.chats[12] = FakeChatsHub.opened.with(HubChatSettings(thinking: thinking))
        }
        return hub
    }

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await Runs.until(what, condition)
    }

    /// Sends `text` on the chat open, and waits for the Mac's rows to take
    /// the reply's place.
    private func say(_ text: String, _ model: AppModel) async throws {
        await model.sendToHubChat(text)?.value
        try await until("the rows after \(text)") { model.hubReplies.isEmpty }
    }

    /// What each turn the Mac was sent said of the choice, in order.
    private func said(_ hub: FakeChatsHub) -> [HubThinking?] {
        hub.with(\.turns).map(\.turn.thinking)
    }

    /// A chat the Mac remembers off opens off, and the switch is not drawn
    /// until the Mac has said so, so it never shows on first. A turn sent
    /// with nothing changed says nothing, and the Mac runs it as it
    /// remembers. A choice made elsewhere is shown when the chat is read
    /// again, and a chat that remembers nothing opens on.
    func testAnOpenedChatShowsWhatTheMacRemembers() async throws {
        let hub = Self.hub(remembering: .off)
        hub.with { $0.holdsOpens = true }
        let (model, config) = try await Runs.makeModel(behind: hub)
        try await until("the list") { model.hubChats[config.id] != nil && model.hubListing.isEmpty }
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the models") { model.models(for: config.id) == Self.models }
        XCTAssertEqual(model.openedHubChat?.state, .reading)
        XCTAssertFalse(model.hubChatOffersThinking, "the switch was drawn before the Mac said what it remembers")
        hub.with { $0.holdsOpens = false }
        try await until("the rows") { model.openedHubChat?.state.showsRows == true }
        XCTAssertTrue(model.hubChatOffersThinking)
        XCTAssertTrue(model.hubThinkingOff, "a chat the Mac remembers off opened on")

        try await say(question, model)
        XCTAssertEqual(hub.with(\.turns).map(\.turn), [HubTurn(conversationID: 12, content: question)])
        XCTAssertTrue(model.hubThinkingOff)

        // Turned back on at the Mac, as its own chat page does.
        hub.with { $0.chats[12] = FakeChatsHub.opened.with(HubChatSettings()) }
        model.hubPipeCameUp(config.id)
        try await until("the chat read again") { !model.hubThinkingOff }
        XCTAssertTrue(model.hubChatOffersThinking)
        try await say(question, model)
        XCTAssertEqual(said(hub), [nil, nil], "a choice made at the Mac was said back to it")

        let (other, _) = try await HubChatContinueTests.opened(Self.hub())
        XCTAssertTrue(other.hubChatOffersThinking)
        XCTAssertFalse(other.hubThinkingOff, "a chat that remembers nothing opened off")
        other.selection = nil
        XCTAssertFalse(other.hubChatOffersThinking, "no chat is open and the switch is offered")
        XCTAssertFalse(other.hubThinkingOff)
    }

    /// The choice goes with the one turn that changes it: `off` to turn
    /// thinking off, and `default`, which tells the Mac to forget, to turn
    /// it back on. The turns before and after say nothing, and neither does
    /// one sent after the switch was set and set back.
    func testAChangeGoesWithTheNextTurnOnceAndBackOnSaysDefault() async throws {
        let hub = Self.hub()
        let (model, _) = try await HubChatContinueTests.opened(hub)
        try await say("one", model)
        model.setHubThinking(off: true)
        XCTAssertTrue(model.hubThinkingOff)
        try await say("two", model)
        XCTAssertTrue(model.hubThinkingOff, "the switch flipped back once its turn was taken")
        try await say("three", model)
        XCTAssertEqual(said(hub), [nil, .off, nil])

        model.setHubThinking(off: false)
        XCTAssertFalse(model.hubThinkingOff)
        try await say("four", model)
        XCTAssertFalse(model.hubThinkingOff)
        try await say("five", model)
        XCTAssertEqual(said(hub), [nil, .off, nil, .default, nil])

        model.setHubThinking(off: true)
        model.setHubThinking(off: false)
        try await say("six", model)
        XCTAssertEqual(said(hub), [nil, .off, nil, .default, nil, nil], "a switch set and set back was said")
        XCTAssertEqual(hub.with(\.turns).map(\.turn.content), ["one", "two", "three", "four", "five", "six"])
    }

    /// Once the Mac takes the turn that says the choice, that is what it
    /// remembers, whether or not its rows can be read again afterwards: the
    /// next turn says nothing. A switch set again while the reply is being
    /// written stays as set, and the turn after says so. A turn taken for
    /// another chat, whose `PUT` may be answered after this one was opened,
    /// says nothing of the chat open.
    func testATurnTheMacTookIsWhatItRemembersAndASwitchSetMeanwhileIsSaidNext() async throws {
        let hub = Self.hub()
        hub.runs.with { $0.holdAt = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.setHubThinking(off: true)
        model.sendToHubChat("one")
        try await until("the first frame") { model.openHubReply?.tools.isEmpty == false }
        hub.with { $0.openFailure = .dropped(nil) }
        hub.runs.release()
        try await until("the end") { model.openHubReply?.ended == true && model.hubReading == nil }
        XCTAssertEqual(hub.with(\.opens), [12, 12], "the rows were not asked for again")
        XCTAssertTrue(model.hubThinkingOff)
        hub.with { $0.openFailure = nil }
        try await say("two", model)
        XCTAssertEqual(said(hub), [.off, nil], "a turn the Mac took was said again")

        hub.runs.with { $0.holdAt = 1 }
        model.setHubThinking(off: false)
        model.sendToHubChat("three")
        try await until("the first frame") { model.openHubReply?.tools.isEmpty == false }
        model.setHubThinking(off: true)
        hub.runs.release()
        try await until("the rows") { model.hubReplies.isEmpty }
        XCTAssertTrue(model.hubThinkingOff, "a switch set while the reply was written flipped back")
        try await say("four", model)
        try await say("five", model)
        XCTAssertEqual(said(hub), [.off, nil, .default, .off, nil])

        let late = HubLiveReply(providerID: config.id, chatID: 9, runID: "late", question: "one", thinking: .default)
        model.hubTookTurn(late)
        XCTAssertTrue(model.hubThinkingOff, "a turn taken for another chat changed the switch of the one open")
    }

    /// A choice set here and taken by the Mac, then changed at the Mac, is
    /// shown when the chat is read again and is not said back to the Mac:
    /// once the Mac remembers what was set here, the switch follows the Mac
    /// again. Both ways round.
    func testAChoiceChangedAtTheMacAfterThisPhoneSetItIsShown() async throws {
        let hub = Self.hub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.setHubThinking(off: true)
        try await say("one", model)
        XCTAssertTrue(model.hubThinkingOff)

        // Turned back on at the Mac, as its own chat page does.
        hub.with { $0.chats[12] = FakeChatsHub.opened.with(HubChatSettings()) }
        model.hubPipeCameUp(config.id)
        try await until("the chat read again") { !model.hubThinkingOff }
        try await say("two", model)
        XCTAssertEqual(said(hub), [.off, nil], "a choice the Mac changed was said back to it")

        // The other way: off at the Mac, on from here, then off at the Mac.
        hub.with { $0.chats[12] = FakeChatsHub.opened.with(HubChatSettings(thinking: .off)) }
        model.hubPipeCameUp(config.id)
        try await until("the chat read again") { model.hubThinkingOff }
        model.setHubThinking(off: false)
        try await say("three", model)
        XCTAssertFalse(model.hubThinkingOff)
        hub.with { $0.chats[12] = FakeChatsHub.opened.with(HubChatSettings(thinking: .off)) }
        model.hubPipeCameUp(config.id)
        try await until("the chat read again") { model.hubThinkingOff }
        try await say("four", model)
        XCTAssertEqual(said(hub), [.off, nil, .default, nil], "the Mac's Off was undone from here")
    }

    /// What the top bar's switch is handed and what a press on it sets, each
    /// the opposite of off and taken in the model: the switch shows on while
    /// the chat is not off, a press to on says `default`, and a press to off
    /// says `off`.
    func testAMacChatsSwitchShowsOnUnlessOffAndAPressSetsWhatItShows() async throws {
        let hub = Self.hub(remembering: .off)
        let (model, _) = try await HubChatContinueTests.opened(hub)
        XCTAssertFalse(model.hubThinkingOn, "a chat the Mac remembers off showed its switch on")
        model.setHubThinking(on: true)
        XCTAssertTrue(model.hubThinkingOn, "a press to on did not show on")
        XCTAssertFalse(model.hubThinkingOff)
        try await say("one", model)
        model.setHubThinking(on: false)
        XCTAssertFalse(model.hubThinkingOn, "a press to off did not show off")
        XCTAssertTrue(model.hubThinkingOff)
        try await say("two", model)
        XCTAssertEqual(said(hub), [.default, .off])
    }

    /// A turn whose answer was lost is put again under its id with the same
    /// body, the choice it was sent with, whatever the switch says by then.
    /// The switch set meanwhile stays as set and is said by the turn after.
    func testATurnPutAgainCarriesTheSameChoice() async throws {
        let hub = Self.hub()
        hub.with { $0.turnsLost = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        model.setHubThinking(off: true)
        model.sendToHubChat(question)
        try await until("the lost answer") { hub.with(\.turns).count == 1 && model.openHubReply?.reading == nil }
        model.setHubThinking(off: false)
        model.hubPipeCameUp(config.id)
        try await until("the turn put again") { hub.with(\.turns).count == 2 }
        try await until("the rows") { model.hubReplies.isEmpty }
        let turns = hub.with(\.turns)
        let sent = HubTurn(conversationID: 12, content: question, thinking: .off)
        XCTAssertEqual(turns.map(\.turn), [sent, sent], "the turn put again was another body")
        XCTAssertEqual(Set(turns.map(\.runID)).count, 1, "the turn was put again under another id")
        XCTAssertFalse(model.hubThinkingOff, "a switch set while its turn was lost flipped back")
        try await say("next", model)
        XCTAssertEqual(said(hub), [.off, .off, .default])
    }

    /// A turn the Mac refuses changed nothing there, so the switch stays as
    /// set and the next turn says the choice again, once.
    func testARefusedTurnKeepsTheChoice() async throws {
        let hub = Self.hub()
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.setHubThinking(off: true)
        hub.with { $0.turnFailure = .noModel }
        await model.sendToHubChat(question)?.value
        XCTAssertEqual(
            model.openedHubChat?.notice, "This chat has no model and nothing is running on home. Start a model there.")
        XCTAssertTrue(model.hubThinkingOff, "a refusal flipped the switch back")
        hub.with { $0.turnFailure = nil }
        try await say(question, model)
        try await say("next", model)
        XCTAssertEqual(said(hub), [.off, .off, nil], "the refused turn, the same sent again, and the one after")
    }

    /// Everything this phone's store holds, as text: each conversation's
    /// fields that could carry a choice, and each provider's row.
    private func kept(_ store: SwiftDataStore) throws -> [String] {
        let conversations = try store.context.fetch(FetchDescriptor<ConversationRecord>()).map { row in
            "conversation \(row.thinkingOff ?? false) \(row.systemPrompt ?? "-") \(row.model ?? "-")"
        }
        let providers = try store.context.fetch(FetchDescriptor<ProviderRecord>()).map { row in
            let chats = row.hubChatsData.map { String(decoding: $0, as: UTF8.self) } ?? "-"
            let runs = row.hubLiveRunsData.map { String(decoding: $0, as: UTF8.self) } ?? "-"
            return "provider \(row.defaultModel ?? "-") \(chats) \(runs)"
        }
        let messages = try store.context.fetchCount(FetchDescriptor<MessageRecord>())
        return conversations + providers + ["messages \(messages)"]
    }

    /// Setting the switch writes nothing to this phone, and neither does the
    /// turn that says it: the store holds what it held, and no conversation
    /// kept here is switched off. A change made and not sent goes with the
    /// chat on Back, and the chat opened again shows what the Mac remembers.
    func testTheChoiceIsNeverStoredAndGoesWithTheChat() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let hub = Self.hub()
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        let before = try kept(store)
        XCTAssertEqual(before.filter { $0.hasPrefix("conversation") }, ["conversation false - mock-27b"])

        model.setHubThinking(off: true)
        XCTAssertFalse(store.context.hasChanges, "setting a Mac chat's switch marked a row")
        XCTAssertEqual(try kept(store), before, "setting a Mac chat's switch wrote to the store")
        XCTAssertEqual(model.conversations.map(\.thinkingOff), [false])
        try await say(question, model)
        XCTAssertEqual(said(hub), [.off])
        XCTAssertEqual(try kept(store), before, "a turn that said the choice wrote to the store")
        XCTAssertFalse(try kept(store).joined().contains("thinking"))

        // Turned back on here and not sent: forgotten on Back.
        model.setHubThinking(off: false)
        XCTAssertFalse(model.hubThinkingOff)
        model.selection = nil
        XCTAssertNil(model.openedHubChat)
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the rows") { model.openedHubChat?.state.showsRows == true }
        XCTAssertTrue(model.hubThinkingOff, "the chat opened again did not show what the Mac remembers")
        try await say("next", model)
        XCTAssertEqual(said(hub), [.off, nil], "a change made and not sent outlived its chat")
        XCTAssertEqual(try kept(store), before)
    }
}
