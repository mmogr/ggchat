import GGChatCore
import XCTest

@testable import GGChatUI

/// A prompt being read, under a reply that has nothing else yet.
final class PromptReadingTests: XCTestCase {
    private let progress = PromptProgress(processed: 8200, total: 11000)

    /// Processed of total, grouped as the locale groups digits.
    @MainActor
    func testTheCountUnderTheBarIsInTheLocalesDigits() {
        func count(_ locale: String) -> String { PromptReading.count(for: progress, in: Locale(identifier: locale)) }
        XCTAssertEqual(count("en_US"), "8,200 of 11,000 tokens")
        XCTAssertEqual(count("de_DE"), "8.200 of 11.000 tokens")
    }

    /// The latest progress, only while it is the latest the reply has heard
    /// and the reply has no reasoning or words: nothing before the first
    /// frame, nothing once a call goes on to a tool until the next call
    /// reads its prompt, and nothing once the first reasoning or word is in.
    @MainActor
    func testAReplyIsReadingItsPromptUntilSomethingElseArrives() {
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            registry: LoopbackProviderRegistry())
        let live = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        XCTAssertNil(live.promptBeingRead, "reading with no progress")
        model.apply(.progress(progress), to: live)
        XCTAssertEqual(live.promptBeingRead, progress)
        model.apply(.tool("Read File"), to: live)
        XCTAssertNil(live.promptBeingRead, "a full bar outlived the tool the call went on to")
        model.apply(.progress(progress), to: live)
        XCTAssertEqual(live.promptBeingRead, progress, "the next call's reading was not shown")
        model.apply(.reasoning("We"), to: live)
        model.apply(.progress(progress), to: live)
        XCTAssertNil(live.promptBeingRead, "the bar took the place of the reasoning")

        let worded = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        model.apply(.delta("Hi"), to: worded)
        model.apply(.progress(progress), to: worded)
        XCTAssertNil(worded.promptBeingRead, "the bar took the place of the words")
    }
}
