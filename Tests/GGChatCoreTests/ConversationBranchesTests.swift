import XCTest

@testable import GGChatCore

/// What a change does to one of this device's conversations (ADR 0010).
final class ConversationBranchesTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func kyoto() -> Conversation {
        Conversation(
            title: "Kyoto", model: "m",
            messages: [
                Message(role: .user, content: "Plan a trip", createdAt: stamp),
                Message(role: .assistant, content: "Day 1", createdAt: stamp, runID: "run-1", runCursor: 4),
            ], systemPrompt: "Be brief.", createdAt: stamp, updatedAt: stamp, thinkingOff: true)
    }

    func testABranchCopiesTheSettingsAndNoRun() throws {
        let original = kyoto()
        let made = try original.applying(.branch(messageID: original.messages[1].id), busy: false, now: stamp)

        XCTAssertTrue(made.isBranch)
        XCTAssertFalse(made.answer)
        let branch = made.conversation
        XCTAssertEqual(
            [branch.title, branch.model, branch.systemPrompt], [original.title, original.model, original.systemPrompt])
        XCTAssertTrue(branch.thinkingOff)
        XCTAssertEqual(branch.messages.map(\.originID), original.messages.map(\.id))
        XCTAssertFalse(branch.messages.contains(where: \.isBeingWritten), "a copy carries a run")
        XCTAssertNil(branch.messages[1].runCursor)
    }

    func testABranchOfABranchIsOfTheFirstFamilyAndCopiesTheFirstMessages() throws {
        let original = kyoto()
        let first = try original.applying(.branch(messageID: original.messages[1].id), busy: false, now: stamp)
            .conversation
        let second = try first.applying(.branch(messageID: first.messages[0].id), busy: false, now: stamp).conversation

        XCTAssertEqual(second.branchOf, first.id)
        XCTAssertEqual(second.familyID, original.id)
        XCTAssertEqual(second.messages.map(\.originID), [original.messages[0].id])
    }

    func testAQuestionEditedInPlaceIsANewMessage() throws {
        var unanswered = kyoto()
        unanswered.messages.removeLast()
        let made = try unanswered.applying(
            .edit(messageID: unanswered.messages[0].id, content: "Plan a long trip", images: []), busy: false,
            now: stamp)

        XCTAssertFalse(made.isBranch)
        XCTAssertTrue(made.answer)
        XCTAssertEqual(made.conversation.id, unanswered.id)
        XCTAssertNotEqual(made.conversation.messages[0].id, unanswered.messages[0].id)
        XCTAssertEqual(made.conversation.messages.map(\.content), ["Plan a long trip"])

        // The rules read an edit's images from the refs it carries, not the
        // ids it names: the same text and image is no change.
        let image = ImageRef(id: "ab", mime: "image/png", width: 1, height: 1)
        var pictured = unanswered
        pictured.messages[0].images = [image]
        XCTAssertThrowsError(
            try pictured.applying(
                .edit(messageID: pictured.messages[0].id, content: "Plan a trip", images: []), images: [image],
                busy: false, now: stamp)
        ) { XCTAssertEqual($0 as? BranchRefusal, .unchanged) }
    }
}
