import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// Edit, regenerate and Branch from here on a Mac's chat (ADR 0010): the
/// change is sent to the Mac naming its row, the chat the Mac names opens,
/// and a question the Mac says to answer is answered by a turn that says
/// `answer_saved`. Nothing of either chat is kept here (ADR 0007).
@MainActor
final class HubChatBranchingTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    /// Chat 13, the Mac's branch of chat 12 as far as its first question,
    /// asked again, with the branch point there.
    static let branch = HubChatOpen(
        conversation: HubConversation(
            id: 13, title: "Why the build broke", modelID: 3, createdAt: "2026-09-30 09:20:05",
            updatedAt: "2026-09-30 09:20:05"),
        messages: [HubMessage(id: 50, conversationID: 13, role: "user", content: "Why did it break?", createdAt: "a")],
        points: [
            BranchPoint(
                messageID: 50, index: 1,
                options: [
                    BranchOption(chatID: 12, messageID: 40, role: .user, preview: "Why did the build break?"),
                    BranchOption(chatID: 13, messageID: 50, role: .user, preview: "Why did it break?"),
                ])
        ],
        answerable: true)

    /// A Mac whose change makes chat 13 and answers as `changed` says.
    static func hub(_ changed: HubChatChanged, _ hub: FakeChatsHub = FakeChatsHub()) -> FakeChatsHub {
        hub.with { state in
            state.chats[13] = branch
            state.changeAnswer = .success(changed)
        }
        return hub
    }

    /// The drawn row of the chat open that says `content`.
    static func row(_ content: String, _ model: AppModel) throws -> UUID {
        guard case .read(let rows)? = model.openedHubChat?.state else { return try XCTUnwrap(nil, "no rows") }
        return try XCTUnwrap(rows.first { $0.content == content }).id
    }

    func testAnEditOfAnAnsweredQuestionOpensTheMacsBranchAndAnswersIt() async throws {
        let hub = Self.hub(HubChatChanged(conversationID: 13, forked: true, answer: true))
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        let kept = try counts(store)

        await model.editHubMessage(try Self.row("Why did the build break?", model), to: " Why did it break? ")?.value

        XCTAssertEqual(hub.with(\.changes).map(\.chatID), [12])
        XCTAssertEqual(
            hub.with(\.changes).map(\.change),
            [HubChatChange(.edit(messageID: 40, content: "Why did it break?", images: []))])
        XCTAssertEqual(model.selection, .hub(providerID: config.id, chatID: 13))
        try await Runs.until("the answer") { !hub.with(\.turns).isEmpty }
        XCTAssertEqual(hub.with(\.turns).map(\.turn), [HubTurn(conversationID: 13, content: "", answerSaved: true)])
        try await Runs.until("the rows after the answer") { model.hubReplies.isEmpty }
        XCTAssertEqual(model.openedHubChat?.points, Self.branch.points)
        XCTAssertEqual(model.openedHubChat?.notice, nil)
        XCTAssertEqual(try counts(store), kept, "the Mac's chats were written to the store")
    }

    private func counts(_ store: SwiftDataStore) throws -> [Int] {
        [
            try store.context.fetchCount(FetchDescriptor<ConversationRecord>()),
            try store.context.fetchCount(FetchDescriptor<MessageRecord>()),
        ]
    }

    func testBranchFromHereOpensTheBranchAndAnswersNothing() async throws {
        let hub = Self.hub(HubChatChanged(conversationID: 13, forked: true, answer: false))
        let (model, config) = try await HubChatContinueTests.opened(hub)

        model.hubMessageChanges { _ in }.branch(try Self.row("A dependency moved.", model))
        try await Runs.until("the change") { !hub.with(\.changes).isEmpty }
        XCTAssertEqual(hub.with(\.changes).map(\.change), [HubChatChange(.branch(messageID: 43))])
        try await Runs.until("the branch's rows") { model.openedHubChat?.points == Self.branch.points }
        XCTAssertEqual(hub.with(\.turns).count, 0, "a branch from here was answered")
        XCTAssertEqual(model.openedHubChat?.answerable, true)

        model.openHubBranch(12)
        XCTAssertEqual(model.selection, .hub(providerID: config.id, chatID: 12))
    }

    /// The Mac's refusal says its rule's sentence, and nothing is opened or
    /// answered; an unchanged edit says nothing.
    func testARefusalSaysTheRulesSentence() async throws {
        let hub = FakeChatsHub()
        hub.with {
            $0.changeAnswer = .failure(.refused(.server(status: 400, code: "not_a_reply", message: "not a reply")))
        }
        let (model, config) = try await HubChatContinueTests.opened(hub)

        model.hubMessageChanges { _ in }.regenerate(try Self.row("Why did the build break?", model))
        try await Runs.until("the refusal") { model.openedHubChat?.notice != nil }

        XCTAssertEqual(hub.with(\.changes).map(\.change), [HubChatChange(.regenerate(messageID: 40))])
        XCTAssertEqual(model.openedHubChat?.notice, "Only a reply can be answered again.")
        XCTAssertEqual(model.selection, .hub(providerID: config.id, chatID: 12))
        XCTAssertEqual(hub.with(\.turns).count, 0)
        hub.with { $0.changeAnswer = .failure(.refused(.server(status: 400, code: "unchanged", message: "same"))) }
        model.openedHubChat?.notice = nil
        await model.regenerateHubMessage(try Self.row("A dependency moved.", model))?.value
        XCTAssertNil(model.openedHubChat?.notice)

        // A row the chat no longer holds is a 404 with the rule's code.
        hub.with {
            $0.changeAnswer = .failure(
                .refused(.server(status: 404, code: "message_not_found", message: "gone")))
        }
        await model.regenerateHubMessage(try Self.row("A dependency moved.", model))?.value
        XCTAssertEqual(model.openedHubChat?.notice, "That message is no longer in this conversation.")
    }

    /// A chat whose question nothing answers is answered by Answer, with
    /// the turn that says `answer_saved`; one that ends in a reply is not.
    func testAnswerAnswersTheQuestionNothingAnswers() async throws {
        let hub = FakeChatsHub()
        let (model, _) = try await HubChatContinueTests.opened(hub)
        XCTAssertNil(model.answerHubChat(), "a chat ending in a reply was answered")

        model.openedHubChat?.answerable = true
        await model.answerHubChat()?.value
        XCTAssertEqual(hub.with(\.turns).map(\.turn), [HubTurn(conversationID: 12, content: "", answerSaved: true)])
    }

    /// The answer says the Thinking choice set on the chat it was asked
    /// from, whether a change or Answer starts it.
    func testTheAnswerSaysTheThinkingChoiceOfTheChatItWasAskedFrom() async throws {
        let hub = Self.hub(
            HubChatChanged(conversationID: 13, forked: true, answer: true), HubChatThinkingTests.hub())
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.setHubThinking(on: false)

        await model.editHubMessage(try Self.row("Why did the build break?", model), to: "Why did it break?")?.value
        try await Runs.until("the answer") { !hub.with(\.turns).isEmpty }
        XCTAssertEqual(hub.with(\.turns).map(\.turn.thinking), [.off])

        try await Runs.until("the rows after the answer") { model.hubReplies.isEmpty }
        model.openHubBranch(12)
        try await Runs.until("chat 12") { model.openedHubChat?.state.showsRows == true }
        model.setHubThinking(on: false)
        model.openedHubChat?.answerable = true
        await model.answerHubChat()?.value
        XCTAssertEqual(hub.with(\.turns).map(\.turn.thinking), [.off, .off])
    }

    /// A branch point names the row that starts its turn, here a reply that
    /// only called a tool and is not drawn: its switcher is drawn at the
    /// reply's first text, once, however many rows of text it has.
    func testAPointAtAReplyThatCalledAToolIsDrawnAtItsText() async throws {
        let hub = FakeChatsHub()
        let point = BranchPoint<Int64, Int64>(
            messageID: 41, index: 0,
            options: [
                BranchOption(chatID: 12, messageID: 41, role: .assistant, preview: "A dependency moved."),
                BranchOption(chatID: 14, messageID: 60, role: .assistant, preview: "The cache was stale."),
            ])
        let more = HubMessage(id: 44, conversationID: 12, role: "assistant", content: "Pin it.", createdAt: "f")
        hub.with {
            $0.chats[12] = HubChatOpen(
                conversation: FakeChatsHub.opened.conversation, messages: FakeChatsHub.opened.messages + [more],
                points: [point])
        }
        let (model, _) = try await HubChatContinueTests.opened(hub)

        XCTAssertEqual(HubChatContinueTests.shown(model).suffix(2), ["A dependency moved.", "Pin it."])
        XCTAssertEqual(model.openedHubChat?.pointAt, [try Self.row("A dependency moved.", model): point])
        XCTAssertNil(model.openedHubChat?.endPoint)
    }

    /// The question a send drew above its reply goes once the rows hold it,
    /// and a turn that answers a saved question draws none.
    func testOnlyASentQuestionIsDrawnAboveItsReply() {
        let sent = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: "Why?")
        XCTAssertEqual(sent.questionToDraw(under: .reading)?.content, "Why?")
        let held = Message(role: .user, content: "Why?", createdAt: .distantPast)
        XCTAssertNil(sent.questionToDraw(under: .read([held])))
        let answer = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: "", answersSaved: true)
        XCTAssertNil(answer.questionToDraw(under: .reading))
        XCTAssertNil(answer.unsent)
    }
}
