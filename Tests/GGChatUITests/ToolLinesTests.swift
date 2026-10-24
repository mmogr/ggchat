import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// A call the model is still writing shows as one line while the reply is
/// read, which a later count of it and then the call itself take the place
/// of, on both doors: a reply kept here and a turn on one of the Mac's chats.
@MainActor
final class ToolLinesTests: XCTestCase {
    private static let events: [ChatEvent] = [
        .tool("Writing Generate Image\u{2026} 1 token", writing: true),
        .tool("Writing Generate Image\u{2026} 512 tokens", writing: true),
        .tool("Generate Image: a fox"),
        .delta("Here it is. "),
        .tool("Writing Read File\u{2026} 9 tokens", writing: true),
        .tool("Read File: Cargo.lock"),
        .tool("List Dir"),
        .tool("Writing Read File\u{2026} 3 tokens", writing: true),
        .tool("Writing List Dir\u{2026} 2 tokens", writing: true),
        .tool("Read File: Package.swift"),
        .tool("List Dir: Sources"),
    ]

    /// What the reply shows after each of `events`.
    private static let shown: [[String]] = [
        ["Writing Generate Image\u{2026} 1 token"],
        ["Writing Generate Image\u{2026} 512 tokens"],
        ["Generate Image: a fox"],
        ["Generate Image: a fox"],
        ["Generate Image: a fox", "Writing Read File\u{2026} 9 tokens"],
        ["Generate Image: a fox", "Read File: Cargo.lock"],
        ["Generate Image: a fox", "Read File: Cargo.lock", "List Dir"],
        ["Generate Image: a fox", "Read File: Cargo.lock", "List Dir", "Writing Read File\u{2026} 3 tokens"],
        ["Generate Image: a fox", "Read File: Cargo.lock", "List Dir", "Writing List Dir\u{2026} 2 tokens"],
        ["Generate Image: a fox", "Read File: Cargo.lock", "List Dir", "Read File: Package.swift"],
        [
            "Generate Image: a fox", "Read File: Cargo.lock", "List Dir", "Read File: Package.swift",
            "List Dir: Sources",
        ],
    ]

    /// Each count replaces the one before, the call replaces its last count,
    /// and a line of a call already written is never replaced: the next
    /// call's line comes under it. Two calls written together show as one
    /// line, the second's count in the first's place, until each call comes.
    func testACallBeingWrittenIsOneLineThatItsCallTakesThePlaceOf() async throws {
        let (model, _) = try await AppModelRunTests.makeModel(behind: FakeRunHub(frames: []))
        let kept = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        let turn = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: nil)
        for (event, shown) in zip(Self.events, Self.shown) {
            model.apply(event, to: kept)
            turn.apply(event)
            XCTAssertEqual(kept.tools, shown, "a reply kept here, after \(event)")
            XCTAssertEqual(turn.tools, shown, "a turn on the Mac's chat, after \(event)")
        }
    }
}
