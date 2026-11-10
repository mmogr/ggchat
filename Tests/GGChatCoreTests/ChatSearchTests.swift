import XCTest

@testable import GGChatCore

/// The list's search: a conversation by its title or what was said in it, a
/// Mac's chat by its title, ignoring case and accents, every word found.
final class ChatSearchTests: XCTestCase {
    private func conversation(title: String = "", _ said: String...) -> Conversation {
        Conversation(
            title: title,
            messages: said.map { Message(role: .user, content: $0, createdAt: Date(timeIntervalSince1970: 0)) },
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testAConversationIsFoundByItsTitleOrAnythingSaidInIt() {
        let chat = conversation(title: "Trip planning", "Book the ferry", "The ferry leaves at nine.")
        XCTAssertTrue(ChatSearch("trip").finds(chat))
        XCTAssertTrue(ChatSearch("LEAVES").finds(chat))
        XCTAssertFalse(ChatSearch("train").finds(chat))
    }

    func testAnUntitledConversationIsFoundByTheTitleItsFirstQuestionGivesIt() {
        XCTAssertTrue(ChatSearch("weather").finds(conversation("Weather in Sydney?")))
    }

    func testEveryWordMustBeFoundInAnyOrderAndInAnyMessage() {
        let chat = conversation("Café opening hours", "Closed on Mondays.")
        XCTAssertTrue(ChatSearch("mondays cafe").finds(chat))
        XCTAssertFalse(ChatSearch("cafe tuesdays").finds(chat))
    }

    func testAMacsChatIsFoundByItsTitle() {
        XCTAssertTrue(ChatSearch("rust").finds(title: "Rust lifetimes"))
        XCTAssertFalse(ChatSearch("swift").finds(title: "Rust lifetimes"))
    }

    func testOnlySpacesSearchForNothing() {
        XCTAssertTrue(ChatSearch("   ").isEmpty)
        XCTAssertTrue(ChatSearch("").finds(conversation("anything")))
    }
}
