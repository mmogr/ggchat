import XCTest

@testable import GGChatCore

/// What a conversation sends is its messages with its system prompt ahead of
/// them, built in one place; the prompt itself is never one of the messages.
final class ConversationTests: XCTestCase {
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func conversation(prompt: String?) -> Conversation {
        Conversation(
            messages: [Message(role: .user, content: "hi", createdAt: stamp)], systemPrompt: prompt,
            createdAt: stamp, updatedAt: stamp)
    }

    func testASystemPromptGoesAheadOfTheMessagesAndIsNotOneOfThem() throws {
        let prompted = conversation(prompt: "Answer in French.")
        XCTAssertTrue(prompted.hasSystemPrompt)
        let sent = prompted.requestMessages
        XCTAssertEqual(sent.map(\.role), [.system, .user])
        let system = try XCTUnwrap(sent.first)
        XCTAssertEqual(system.content, "Answer in French.")
        XCTAssertEqual(system.id, Conversation.systemPromptMessageID)
        XCTAssertEqual(system.createdAt, stamp, "the turn is dated by the conversation, not by the clock")
        XCTAssertNil(system.reasoning)
        XCTAssertFalse(system.isPartial)
        XCTAssertEqual(Array(sent.dropFirst()), prompted.messages, "the transcript follows the prompt unchanged")
        XCTAssertEqual(prompted.messages.map(\.role), [.user], "the prompt became a turn in the transcript")
        XCTAssertFalse(prompted.messages.contains { $0.id == Conversation.systemPromptMessageID })
        XCTAssertEqual(prompted.derivedTitle, "hi", "the title comes from the first question, not the prompt")
    }

    func testABlankSystemPromptSendsNothingExtra() {
        for prompt in [nil, "", "  \n"] as [String?] {
            let blank = conversation(prompt: prompt)
            XCTAssertFalse(blank.hasSystemPrompt, "\(String(describing: prompt)) counted as a prompt")
            XCTAssertEqual(blank.requestMessages, blank.messages, "\(String(describing: prompt)) sent a turn")
        }
        let prompted = conversation(prompt: "Answer in French.")
        XCTAssertEqual(
            prompted.requestMessages, prompted.requestMessages,
            "two requests built from one conversation differ, so equal requests can never be told equal")
        XCTAssertEqual(
            ChatRequest(model: "m", messages: prompted.requestMessages),
            ChatRequest(model: "m", messages: prompted.requestMessages))
    }

    /// A conversation whose first turn is images alone is called what that
    /// turn holds; one with text is still called by its first line.
    func testAFirstTurnOfImagesAloneIsCalledWhatItHolds() {
        let image = ImageRef(id: "ab", mime: ImageRef.png, width: 1, height: 1)
        let other = ImageRef(id: "cd", mime: ImageRef.jpeg, width: 1, height: 1)
        func titled(_ text: String, _ images: [ImageRef]) -> String {
            Conversation(
                messages: [Message(role: .user, content: text, createdAt: stamp, images: images)], createdAt: stamp,
                updatedAt: stamp
            ).derivedTitle
        }
        XCTAssertEqual(titled("", [image]), "An image")
        XCTAssertEqual(titled("", [image, other]), "2 images")
        XCTAssertEqual(titled("what is this\nand this", [image]), "what is this")
        XCTAssertEqual(titled("", []), "")
    }
}
