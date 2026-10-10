import XCTest

@testable import GGChatCore

/// The branching rules beyond gglib's recorded cases: the line an option is
/// shown by, and the same rules over this device's own ids, a chat's UUID
/// and a message's time, as its local conversations use them.
final class BranchRulesTests: XCTestCase {
    private typealias Row = LineRow<Int, Int>

    func testAQuestionIsShownByItsFirstLineCutAtEightyCharacters() {
        let long = String(repeating: "é", count: 85)
        XCTAssertEqual(
            BranchRules.preview([Row(id: 1, key: 1, role: .user, text: "\n  Plan a trip\nto Kyoto")]), "Plan a trip")
        XCTAssertEqual(
            BranchRules.preview([Row(id: 1, key: 1, role: .user, text: long)]), String(repeating: "é", count: 80) + "…")
        // Rust's `lines` ends a line at `\r\n` too.
        XCTAssertEqual(
            BranchRules.preview([Row(id: 1, key: 1, role: .user, text: "Plan a trip\r\nto Kyoto")]), "Plan a trip")
        XCTAssertEqual(
            BranchRules.preview([Row(id: 1, key: 1, role: .user, text: " \r\n\r\nPlan a trip\r\n")]), "Plan a trip")
    }

    func testAQuestionOfImagesAloneSaysHowMany() {
        XCTAssertEqual(BranchRules.preview([Row(id: 1, key: 1, role: .user, text: "", images: 1)]), "An image")
        XCTAssertEqual(BranchRules.preview([Row(id: 1, key: 1, role: .user, text: " ", images: 3)]), "3 images")
    }

    func testAReplyIsShownByItsLastLineOfText() {
        let reply = [
            Row(id: 2, key: 2, role: .assistant, text: "Looking it up"),
            Row(id: 3, key: 3, role: .tool, text: "{\"rain\": true}"),
            Row(id: 4, key: 4, role: .assistant, text: "Take an umbrella."),
        ]
        XCTAssertEqual(BranchRules.preview(reply), "Take an umbrella.")
        XCTAssertEqual(BranchRules.preview([Row(id: 2, key: 2, role: .assistant, text: "")]), "(no text)")
    }

    func testAFamilyOfThisDevicesChatsPartsWhereItsTurnsDiffer() {
        let (first, second) = (UUID(), UUID())
        let (question, reply, other) = (UUID(), UUID(), UUID())
        let start = Date(timeIntervalSince1970: 1_000)
        let shared = LineRow(id: question, key: question, role: .user, text: "Plan a trip to Kyoto")
        let family = [
            LineChat(
                chatID: first, updatedAt: start,
                rows: [shared, LineRow(id: reply, key: reply, role: .assistant, text: "Day 1: temples")]),
            LineChat(
                chatID: second, updatedAt: start.addingTimeInterval(60),
                rows: [shared, LineRow(id: other, key: other, role: .assistant, text: "Day 1: gardens")]),
        ]

        let points = BranchRules.points(second, family: family)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.messageID, other)
        XCTAssertEqual(points.first?.options.map(\.chatID).sorted(), [first, second].sorted())
        XCTAssertEqual(points.first?.options[points.first?.index ?? 0].chatID, second)
    }

    /// A reply saved as it was is refused as unchanged; with images it is
    /// refused for the images first, with gglib's code.
    func testAReplyEditedToItsOwnTextIsRefused() {
        let path = [
            BranchRow(id: 1, role: .user, content: "Plan a trip"),
            BranchRow(id: 2, role: .assistant, content: "Day 1: temples"),
        ]
        XCTAssertThrowsError(
            try BranchRules.plan(path, .edit(messageID: 2, content: "Day 1: temples", images: []), busy: false)
        ) {
            XCTAssertEqual($0 as? BranchRefusal, .unchanged)
        }
        XCTAssertThrowsError(
            try BranchRules.plan(path, .edit(messageID: 2, content: "Day 1: temples", images: ["a"]), busy: false)
        ) {
            XCTAssertEqual(($0 as? BranchRefusal)?.code, "invalid_request")
        }
    }

    /// Of two chats that go on the same way, changed at the same moment, the
    /// one with the higher id stands for the option, as gglib picks it.
    func testATieInTimeIsBrokenByTheHigherChatID() {
        let start = Date(timeIntervalSince1970: 1_000)
        let question = LineRow(id: 1, key: 1, role: .user, text: "Plan a trip")
        func chat(_ id: Int, _ reply: LineRow<Int, Int>) -> LineChat<Int, Int, Int, Date> {
            LineChat(chatID: id, updatedAt: start, rows: [question, reply])
        }
        let temples = LineRow(id: 2, key: 2, role: .assistant, text: "Day 1: temples")
        let family = [
            chat(5, LineRow(id: 3, key: 3, role: .assistant, text: "Day 1: gardens")), chat(6, temples),
            chat(7, temples),
        ]
        XCTAssertEqual(BranchRules.points(5, family: family).first?.options.map(\.chatID), [7, 5])
    }

    func testAnEditOfTheLastQuestionIsMadeInPlaceOnlyWhileNothingIsWritingItsReply() throws {
        let path = [BranchRow(id: UUID(), role: .user, content: "Plan a trip")]
        let edit = ChatChange.edit(messageID: path[0].id, content: "Plan a short trip", images: [])
        XCTAssertEqual(try BranchRules.plan(path, edit, busy: false), .replace(question: path[0].id))
        XCTAssertEqual(try BranchRules.plan(path, edit, busy: true), .fork(through: nil, then: .question, answer: true))
    }
}
