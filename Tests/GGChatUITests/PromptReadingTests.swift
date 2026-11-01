import GGChatCore
import XCTest

@testable import GGChatUI

/// A prompt being read, under a reply that has nothing else yet.
final class PromptReadingTests: XCTestCase {
    private let progress = PromptProgress(processed: 57, total: 57)

    /// The latest progress, only while it is the latest the reply has heard
    /// and the reply has no thought or word: a call that has read its prompt
    /// and gone on to a tool shows no full count while the tool runs, the
    /// next call's reading is shown, and none is once the reply has thought.
    @MainActor
    func testAReplyHoldsItsProgressOnlyUntilAnythingElseArrives() {
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            registry: LoopbackProviderRegistry())
        let live = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        let english = Locale(identifier: "en_US")
        model.apply(.progress(progress), to: live)
        XCTAssertEqual(live.readingLine(in: english), "Reading 57 of 57 tokens")
        model.apply(.tool("Read File"), to: live)
        XCTAssertNil(live.readingLine(in: english), "a full count outlived the tool the call went on to")
        model.apply(.progress(PromptProgress(processed: 64, total: 90)), to: live)
        XCTAssertEqual(
            live.readingLine(in: english), "Reading 64 of 90 tokens", "the next call's reading was not shown")
        model.apply(.reasoning("We"), to: live)
        model.apply(.progress(progress), to: live)
        XCTAssertNil(live.readingLine(in: english), "a count took the place of the reasoning")
    }
}
