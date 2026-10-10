import GGChatCore
import XCTest

@testable import GGChatUI

/// How the switcher at a branch point says where the open conversation is,
/// and how it lists the options (ADR 0010).
final class BranchSwitcherTests: XCTestCase {
    private func option(_ preview: String, message: UUID? = UUID()) -> BranchOption<UUID, UUID> {
        BranchOption(chatID: UUID(), messageID: message, role: message == nil ? nil : .assistant, preview: preview)
    }

    @MainActor
    func testTheSwitcherSaysWhichOfHowManyTheOpenConversationIs() {
        let point = BranchPoint(messageID: UUID(), index: 1, options: [option("a"), option("b"), option("c")])
        let choice = BranchChoice(point) { _ in }
        XCTAssertEqual(choice.position, "2/3")
        XCTAssertEqual(choice.spokenPosition, "Branch 2 of 3")
    }

    @MainActor
    func testAnOptionIsListedByItsLineOrWhatStandsInForOne() {
        var opened: [UUID] = []
        let options = [option("a"), option("b")]
        BranchChoice(BranchPoint(messageID: UUID(), index: 0, options: options)) { opened.append($0) }.open(1)
        XCTAssertEqual(opened, [options[1].chatID], "an option opened another chat")
        XCTAssertEqual(BranchChoice.line(for: option("Day 1: temples")), "Day 1: temples")
        XCTAssertEqual(BranchChoice.line(for: option("")), "(no text)")
        XCTAssertEqual(BranchChoice.line(for: option("", message: nil)), "Nothing here yet")
    }
}
