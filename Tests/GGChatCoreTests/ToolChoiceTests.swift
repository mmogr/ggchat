import Foundation
import XCTest

@testable import GGChatCore

/// Which of a paired Mac's servers a conversation names: its picks, under a
/// master switch, narrowed to what the Mac offers when that is known.
final class ToolChoiceTests: XCTestCase {
    private let tavily = OfferedServer(id: 3, name: "tavily")
    private let files = OfferedServer(id: 9, name: "fs")

    /// A new conversation's choice is on, picks nothing and names nothing,
    /// whatever the Mac offers.
    func testANewChoiceNamesNoServer() {
        let choice = ToolChoice()
        XCTAssertFalse(choice.off)
        XCTAssertTrue(choice.isDefault)
        XCTAssertEqual(choice.servers(offered: [tavily, files]), [])
        XCTAssertEqual(choice.servers(offered: nil), [])
    }

    /// A pick is named while the Mac offers it, and not once it stops,
    /// though it is kept; the names are sorted.
    func testPicksAreNamedOnlyWhileTheMacOffersThem() {
        let choice = ToolChoice().picking(9, true).picking(3, true).picking(12, true)
        XCTAssertEqual(choice.servers(offered: [tavily, files]), [3, 9])
        XCTAssertEqual(choice.servers(offered: [files]), [9])
        XCTAssertEqual(choice.servers(offered: []), [])
        XCTAssertEqual(choice.picked, [3, 9, 12], "a pick the Mac stopped offering was dropped")
        XCTAssertEqual(choice.picking(9, false).servers(offered: [tavily, files]), [3])
    }

    /// Turned off, the choice names nothing and keeps its picks, so turning
    /// it on again names them again.
    func testTurnedOffNamesNoneAndKeepsThePicks() {
        let picked = ToolChoice().picking(3, true)
        let off = picked.turned(on: false)
        XCTAssertTrue(off.off)
        XCTAssertEqual(off.servers(offered: [tavily]), [])
        XCTAssertEqual(off.servers(offered: nil), [])
        XCTAssertEqual(off.picked, [3])
        XCTAssertEqual(off.turned(on: true), picked)
    }

    /// While the Mac's offer is not known every pick is named as kept, for
    /// the Mac to narrow to those it opens.
    func testAnUnheardMacIsNamedThePicksAsKept() {
        let choice = ToolChoice(picked: [12, 3])
        XCTAssertEqual(choice.servers(offered: nil), [3, 12])
    }

    /// What a conversation has seen is kept when the Mac stops offering a
    /// server, as a pick is.
    func testSeenOutlivesAServerTheMacClosed() {
        let choice = ToolChoice().seeing([3, 9]).seeing([3])
        XCTAssertEqual(choice.seen, [3, 9])
        XCTAssertFalse(choice.isDefault)
    }

    /// What is unseen is what the Mac offers now that the conversation has
    /// never shown: not a server it showed and the Mac then closed, nor one
    /// it showed under another name.
    func testUnseenIsWhatTheMacOffersThatThisChatNeverShowed() {
        let choice = ToolChoice(seen: [3, 12])
        XCTAssertEqual(choice.unseen(offered: [tavily, files]), [9])
        XCTAssertEqual(choice.unseen(offered: [OfferedServer(id: 3, name: "Tavily Web Search")]), [])
        XCTAssertEqual(ToolChoice().unseen(offered: [tavily, files]), [3, 9])
        XCTAssertEqual(choice.seeing([9]).unseen(offered: [tavily, files]), [])
    }

    /// A pick is by id, so a server the Mac renames is still picked.
    func testAPickSurvivesARename() {
        let choice = ToolChoice().picking(3, true)
        XCTAssertEqual(choice.servers(offered: [OfferedServer(id: 3, name: "Tavily Web Search")]), [3])
        XCTAssertEqual(choice.servers(offered: [OfferedServer(id: 4, name: "tavily")]), [])
    }

    /// Every key is written, the sets as sorted lists, and a choice read
    /// back is the one written.
    func testItEncodesEveryKeySorted() throws {
        let choice = ToolChoice(off: false, picked: [9, 3], seen: [12, 9, 3])
        let data = try JSONEncoder().encode(choice)
        XCTAssertEqual(
            try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary),
            ["off": false, "picked": [3, 9], "seen": [3, 9, 12]] as NSDictionary)
        XCTAssertEqual(try JSONDecoder().decode(ToolChoice.self, from: data), choice)
        let empty = try JSONEncoder().encode(ToolChoice())
        XCTAssertEqual(
            try XCTUnwrap(JSONSerialization.jsonObject(with: empty) as? NSDictionary),
            ["off": false, "picked": [], "seen": []] as NSDictionary)
    }
}
