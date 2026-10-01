import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// The rows a reply streams into read its blocks from the reply, as each
/// token redraws them. Every read must match a parse of the whole content,
/// and none may parse the blocks that came before the last one or two.
final class LiveReplyMarkdownTests: XCTestCase {
    private let reply = (1...30).map { step in
        "## Step \(step)\n\nProse for step \(step), long enough to be a line of its own.\n\n"
            + "```swift\nlet step = \(step)\n```\n\n| k | v |\n|---|---|\n| \(step) | \(step * 2) |\n\n"
    }
    .joined()

    private var tokens: [String] {
        let characters = Array(reply)
        return stride(from: 0, to: characters.count, by: 5).map {
            String(characters[$0..<min($0 + 5, characters.count)])
        }
    }

    /// The blocks `read` gives, and the bytes parsed while it ran, by any
    /// path to the parser.
    @MainActor
    private func measured(_ read: () -> [MarkdownBlock]) -> (blocks: [MarkdownBlock], bytes: Int) {
        let meter = ParseMeter()
        let blocks = ParseMeter.$current.withValue(meter, operation: read)
        return (blocks, meter.bytes)
    }

    @MainActor
    func testTheChatRowParsesOnlyWhatATokenCanChange() {
        let live = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        var most = 0
        var total = 0
        for token in tokens {
            live.content += token
            let (blocks, bytes) = measured { live.blocks }
            most = max(most, bytes)
            total += bytes
            guard blocks == MarkdownBlocks.parse(live.content) else {
                return XCTFail("at \(live.content.debugDescription)")
            }
        }
        XCTAssertLessThan(most, 600, "a token parsed \(most) bytes of a \(reply.utf8.count)-byte reply")
        XCTAssertGreaterThanOrEqual(total, reply.utf8.count, "every byte was parsed at least once")
    }

    @MainActor
    func testAMacChatRowParsesOnlyWhatADeltaCanChange() {
        let hub = HubLiveReply(providerID: UUID(), chatID: 1, runID: "run", question: nil)
        var most = 0
        var total = 0
        for token in tokens {
            hub.apply(.delta(token))
            let (blocks, bytes) = measured { hub.blocks }
            most = max(most, bytes)
            total += bytes
            guard blocks == MarkdownBlocks.parse(hub.content) else {
                return XCTFail("at \(hub.content.debugDescription)")
            }
        }
        XCTAssertLessThan(most, 600, "a delta parsed \(most) bytes of a \(reply.utf8.count)-byte reply")
        XCTAssertGreaterThanOrEqual(total, reply.utf8.count, "every byte was parsed at least once")
    }
}
