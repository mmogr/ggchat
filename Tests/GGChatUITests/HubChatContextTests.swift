import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The context reading of a Mac's chat: read from the rows the Mac saved,
/// replaced by what a reply in hand counts, held in memory with the chat and
/// never written to this phone (ADR 0007).
@MainActor
final class HubChatContextTests: XCTestCase {
    private let question = "And how do I fix it?"
    private let english = Locale(identifier: "en_US")
    /// What the Mac saved beside chat 12's last reply.
    private static let saved = HubMessageMetadata(
        device: "phone-7c2e", modelName: "qwen3-8b", promptTokens: 812, completionTokens: 96, contextSize: 8_192,
        trimmedMessages: 2, finishReason: "stop")

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// Chat 12 as the Mac holds it, its last reply saved with `metadata`,
    /// and then `more` rows.
    private static func chat(_ metadata: HubMessageMetadata?, then more: [HubMessage] = []) -> HubChatOpen {
        var rows = FakeChatsHub.opened.messages
        let last = rows.removeLast()
        rows.append(
            HubMessage(
                id: last.id, conversationID: 12, role: last.role, content: last.content, createdAt: last.createdAt,
                metadata: metadata))
        return HubChatOpen(conversation: FakeChatsHub.opened.conversation, messages: rows + more)
    }

    /// A turn the Mac saved after those: the question, and a reply.
    private func turn(_ answer: String, _ metadata: HubMessageMetadata?) -> [HubMessage] {
        [
            HubMessage(id: 44, conversationID: 12, role: "user", content: question, createdAt: "f"),
            HubMessage(
                id: 45, conversationID: 12, role: "assistant", content: answer, createdAt: "g", metadata: metadata),
        ]
    }

    /// Opens chat 12 again, so its rows are read again.
    private func reopen(_ model: AppModel, on config: ProviderConfig) async throws {
        model.selection = nil
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await until("the rows") { model.openedHubChat?.state.showsRows == true }
    }

    /// An opened chat draws the reading its last reply's row carries, and
    /// none when the rows carry no counts, as an older gglib's do. A reply
    /// that did not finish and has no counts leaves the one before it, and
    /// Back drops the reading with the chat.
    func testAnOpenedChatShowsItsLastRepliesReading() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        XCTAssertNil(model.hubContextReading, "rows with no counts drew a ring")

        let finished = Self.chat(Self.saved)
        hub.with { $0.chats[12] = finished }
        try await reopen(model, on: config)
        let reading = try XCTUnwrap(model.hubContextReading)
        XCTAssertEqual(reading, ContextReading(Self.saved))
        XCTAssertNil(reading.model)
        XCTAssertEqual(
            reading.lines(in: english),
            [
                "908 of 8,192 tokens (11%) after the last finished reply.",
                "2 earlier messages were shortened or left out to fit.",
            ])

        // As gglib's recorded chat ends: a reply that did not finish, with
        // only the mark beside it.
        let stopped = Self.chat(Self.saved, then: turn("Pin the", HubMessageMetadata(incomplete: true)))
        hub.with { $0.chats[12] = stopped }
        try await reopen(model, on: config)
        XCTAssertEqual(model.hubContextReading, reading, "an unfinished reply moved the reading")

        let unsized = Self.chat(
            Self.saved,
            then: turn("Pin the version.", HubMessageMetadata(promptTokens: 900, completionTokens: 12)))
        hub.with { $0.chats[12] = unsized }
        try await reopen(model, on: config)
        XCTAssertNil(model.hubContextReading, "an older reply's reading was drawn for a newer one with no size")

        hub.with { $0.chats[12] = finished }
        try await reopen(model, on: config)
        XCTAssertEqual(model.hubContextReading, reading)
        model.selection = nil
        XCTAssertNil(model.hubContextReading, "Back kept the reading")
        XCTAssertEqual(model.conversations.map(\.context), [nil])
    }

    /// While a reply is in hand, what its last finished call counted is the
    /// reading, each call's over the one before; until it has counted
    /// anything the rows' reading stays. A call that reports no size hides
    /// the ring. Once the run ends the Mac's rows decide again.
    func testALiveCallReplacesItAndOneWithNoSizeHidesIt() async throws {
        let first = Usage(promptTokens: 1_000, completionTokens: 30, contextSize: 8_192)
        let last = Usage(promptTokens: 6_000, completionTokens: 400, contextSize: 8_192, trimmedMessages: 1)
        let reply: [[ChatEvent]] = [
            [.tool("Read File: Cargo.lock")], [.usage(first, reason: "tool_calls")], [.delta("Pin the version.")],
            [.usage(last, reason: "length")],
        ]
        let before = Self.chat(Self.saved)
        let fromRows = try XCTUnwrap(ContextReading(Self.saved))
        let written = HubMessageMetadata(promptTokens: 6_000, completionTokens: 400, contextSize: 8_192)
        let after = Self.chat(Self.saved, then: turn("Pin the version.", written))
        let cutOff = try XCTUnwrap(ContextReading(last, reason: "length"))
        XCTAssertEqual(cutOff.lines(in: english).last, "The last reply was cut off before it finished.")
        let wanted: [(held: UInt32, reading: ContextReading?)] = [
            (1, fromRows), (2, ContextReading(first, reason: "tool_calls")), (4, cutOff),
        ]
        for (held, reading) in wanted {
            let want = try XCTUnwrap(reading)
            let hub = FakeChatsHub(reply: reply)
            hub.with { $0.chats[12] = before }
            hub.runs.with { $0.holdAt = held }
            let (model, _) = try await HubChatContinueTests.opened(hub)
            XCTAssertEqual(model.hubContextReading, fromRows)
            model.sendToHubChat(question)
            try await until("\(held) frames") { model.openHubReply?.cursor == held }
            XCTAssertEqual(model.hubContextReading, want, "after \(held) frames")

            hub.with { $0.chats[12] = after }
            hub.runs.release()
            try await until("the Mac's rows") { model.hubReplies.isEmpty }
            XCTAssertEqual(model.hubContextReading, ContextReading(written), "the rows did not decide once it ended")
        }

        let unsized = FakeChatsHub(reply: [[.usage(Usage(completionTokens: 12), reason: nil)], [.delta("Pin it.")]])
        unsized.with { $0.chats[12] = before }
        unsized.runs.with { $0.holdAt = 1 }
        let (model, _) = try await HubChatContinueTests.opened(unsized)
        XCTAssertEqual(model.hubContextReading, fromRows)
        model.sendToHubChat(question)
        try await until("the counts") { model.openHubReply?.usage != nil }
        XCTAssertNil(model.hubContextReading, "a call with no size left the old reading up")
        unsized.runs.release()
        try await until("the Mac's rows") { model.hubReplies.isEmpty }
        XCTAssertEqual(model.hubContextReading, fromRows, "the rows did not decide once it ended")
    }

    /// A chat the Mac stops sending draws no ring over the sentence that says
    /// so: when the Mac no longer has it, and when it no longer shares its
    /// chats. Read again, it has none until its rows land. A reply that ends
    /// and whose rows cannot be read in its place has none either, though
    /// its counts are still in hand.
    func testAChatTheMacStopsSendingDrawsNoRing() async throws {
        let finished = Self.chat(Self.saved)
        let fromRows = try XCTUnwrap(ContextReading(Self.saved))
        let live = Usage(promptTokens: 6_000, completionTokens: 400, contextSize: 8_192)
        let refusals: [(failure: HubChatsFailure, why: String)] = [
            (.notFound, "home no longer has this chat."),
            (.notShared, "home does not share its chats with this phone."),
        ]
        for (failure, why) in refusals {
            let hub = FakeChatsHub()
            hub.with { $0.chats[12] = finished }
            let (model, _) = try await HubChatContinueTests.opened(hub)
            XCTAssertEqual(model.hubContextReading, fromRows)
            hub.with { $0.openFailure = failure }
            model.readHubChat()
            try await until("the refusal") { model.openedHubChat?.state == .unavailable(why) }
            XCTAssertNil(model.hubContextReading, "the old ring stayed over \"\(why)\"")

            hub.with { state in
                state.openFailure = nil
                state.holdsOpens = true
            }
            model.readHubChat()
            XCTAssertEqual(model.openedHubChat?.state, .reading)
            XCTAssertNil(model.hubContextReading, "the old ring came back while the chat was read again")
            hub.with { $0.holdsOpens = false }
            try await until("the rows") { model.openedHubChat?.state.showsRows == true }
            XCTAssertEqual(model.hubContextReading, fromRows)

            let ending = FakeChatsHub(reply: [[.usage(live, reason: "stop")], [.delta("Pin the version.")]])
            ending.with { $0.chats[12] = finished }
            ending.runs.with { $0.holdAt = 1 }
            let (replied, _) = try await HubChatContinueTests.opened(ending)
            replied.sendToHubChat(question)
            try await until("the counts") { replied.openHubReply?.usage != nil }
            XCTAssertEqual(replied.hubContextReading, ContextReading(live, reason: "stop"))
            ending.with { $0.openFailure = failure }
            ending.runs.release()
            try await until("the refusal") { replied.openedHubChat?.state == .unavailable(why) }
            XCTAssertEqual(replied.openHubReply?.usage, live, "the ended reply's counts are no longer in hand")
            XCTAssertNil(replied.hubContextReading, "a reply that ended kept its ring over \"\(why)\"")
        }
    }

    /// Nothing of a Mac's chat's reading reaches the store: not from the
    /// rows, not from a reply in hand, not when the run ends and not on
    /// Back. The conversation kept here is as it was, no row holds a
    /// reading, the provider's row holds the titles and nothing more, and a
    /// relaunch on the same store has no reading to draw.
    func testNoReadingIsWrittenToThePhone() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let live = Usage(promptTokens: 6_000, completionTokens: 400, contextSize: 8_192)
        let hub = FakeChatsHub(reply: [[.usage(live, reason: "stop")], [.delta("Pin the version.")]])
        let chat = Self.chat(Self.saved)
        hub.with { $0.chats[12] = chat }
        hub.runs.with { $0.holdAt = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        let before = try store.loadConversations()
        XCTAssertEqual(before.count, 1)
        let titles = FakeChatsHub.summaries.map { SeenHubChat(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
        func nothingWasWritten(_ when: String) throws {
            XCTAssertEqual(try store.loadConversations(), before, when)
            let rows = try store.context.fetch(FetchDescriptor<ConversationRecord>())
            XCTAssertEqual(rows.map(\.contextData), [nil], when)
            XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<MessageRecord>()), 0, when)
            XCTAssertEqual(try store.loadHubChats(forProvider: config.id)?.chats, titles, when)
            XCTAssertEqual(model.conversations.map(\.context), [nil], when)
        }

        XCTAssertEqual(model.hubContextReading, ContextReading(Self.saved))
        try nothingWasWritten("with the rows' reading drawn")
        model.sendToHubChat(question)
        try await until("the counts") { model.openHubReply?.usage != nil }
        XCTAssertEqual(model.hubContextReading, ContextReading(live, reason: "stop"))
        try nothingWasWritten("with a reply's counts in hand")
        hub.runs.release()
        try await until("the Mac's rows") { model.hubReplies.isEmpty }
        XCTAssertNotNil(model.hubContextReading)
        try nothingWasWritten("once the run ended")
        model.selection = nil
        XCTAssertNil(model.hubContextReading)
        try nothingWasWritten("after Back")

        let registry = LoopbackProviderRegistry()
        let relaunched = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "HubChatContextTests.\(UUID().uuidString)")!))
        relaunched.load()
        XCTAssertNil(relaunched.hubContextReading)
        XCTAssertEqual(relaunched.conversations.map(\.context), [nil])
    }
}
