import GGChatCore
import XCTest

@testable import GGChatUI

/// The wrench in a chat's top bar, and its rows in the panel beside a chat
/// on an open iPhone Duo: a master switch and a pick for each server the
/// paired Mac offers, in its order, shown only where tools are offered.
@MainActor
final class ToolsMenuTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private let tavily = OfferedServer(id: 3, name: "tavily")
    private let files = OfferedServer(id: 9, name: "fs")

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    /// A Mac whose answer names no servers, one from before the list and
    /// one not heard from have no wrench.
    func testHiddenWhereTheMacOffersNone() async throws {
        let none = Drawing(available: true, model: "flux-dev", mcpServers: [])
        for drawing in [none, DrawingRunTests.can, nil] {
            let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: drawing)
            let conversation = try XCTUnwrap(model.selectedConversation)
            XCTAssertTrue(model.toolsMenu(for: conversation).isHidden, String(describing: drawing))
        }
    }

    /// A gglib reached by address has no wrench whatever it says of its
    /// servers, and a Mac's own chat has no tools part in its panel: it
    /// keeps its tools on the Mac.
    func testHiddenOnAMacsChatAndByAddress() async throws {
        let (byAddress, config) = try await Runs.makeModel(behind: hub(), direct: true)
        byAddress.drawings[config.id] = .offersTavily
        XCTAssertTrue(byAddress.toolsMenu(for: try XCTUnwrap(byAddress.selectedConversation)).isHidden)
        let parts = ThisChatPart.parts(
            isMacsChat: true, thinks: false, offersTools: true, hasContext: false, reportsStatus: false)
        XCTAssertFalse(parts.contains(.tools))
        XCTAssertEqual(ToolsMenu.hidden.rows, [])
    }

    /// A row for each server the Mac offers, in its order, each picked or
    /// not as the conversation chose, and a pick it no longer offers is
    /// neither a row nor counted.
    func testRowsAreTheMacsServersInItsOrder() {
        let menu = ToolsMenu(choice: ToolChoice(picked: [9, 12]), offered: [tavily, files])
        XCTAssertEqual(menu.rows.map(\.id), [3, 9])
        XCTAssertEqual(menu.rows.map(\.title), ["tavily", "fs"])
        XCTAssertEqual(menu.rows.map(\.picked), [false, true])
        XCTAssertEqual(menu.running, [9])
        XCTAssertFalse(menu.isHidden)
    }

    /// Two servers of one name each show their id after it; a name no other
    /// server has shows alone, and the status sheet lists them alike.
    func testASharedNameShowsEachServersID() {
        let servers = [OfferedServer(id: 4, name: "fs"), files, tavily]
        XCTAssertEqual(ToolsMenu.titles(servers), ["fs (4)", "fs (9)", "tavily"])
        XCTAssertEqual(
            ToolsMenu(choice: ToolChoice(), offered: servers).rows.map(\.title), ["fs (4)", "fs (9)", "tavily"])
    }

    /// Off, none picked, one server and several: each says its state in
    /// words, and the wrench is filled only while a server would be named.
    func testLabelsAndSymbols() {
        let choices = [
            ToolChoice(off: true, picked: [3]), ToolChoice(), ToolChoice(picked: [12]), ToolChoice(picked: [3]),
            ToolChoice(picked: [3, 9]),
        ]
        let menus = choices.map { ToolsMenu(choice: $0.seeing([3, 9]), offered: [tavily, files]) }
        XCTAssertEqual(
            menus.map(\.label),
            ["Tools, off", "Tools, none picked", "Tools, none picked", "Tools, 1 server", "Tools, 2 servers"])
        let (outline, filled) = ("wrench.and.screwdriver", "wrench.and.screwdriver.fill")
        XCTAssertEqual(menus.map(\.symbol), [outline, outline, outline, filled, filled])
    }

    /// Off, every row is still there with its pick, and nothing is named.
    func testOffKeepsEveryRowAndItsPickAndNamesNone() {
        let menu = ToolsMenu(choice: ToolChoice(off: true, picked: [3]), offered: [tavily, files])
        XCTAssertFalse(menu.isOn)
        XCTAssertEqual(menu.rows.map(\.picked), [true, false])
        XCTAssertEqual(menu.running, [])
    }

    /// A pick, a drop and the master switch each write the conversation and
    /// leave its date alone.
    func testPickingLeavesUpdatedAtAlone() async throws {
        let store = InMemoryStore()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily, store: store)
        let conversation = try XCTUnwrap(model.selectedConversation)
        model.setServer(3, picked: true, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.toolChoice, ToolChoice(picked: [3], seen: [3]))
        XCTAssertEqual(model.toolsMenu(for: try XCTUnwrap(model.selectedConversation)).label, "Tools, 1 server")
        model.setTools(on: false, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.toolChoice, ToolChoice(off: true, picked: [3], seen: [3]))
        model.setServer(3, picked: false, for: conversation.id)
        let stored = try XCTUnwrap(try store.loadConversations().first { $0.id == conversation.id })
        XCTAssertEqual(stored.toolChoice, ToolChoice(off: true, seen: [3]))
        XCTAssertEqual(stored.updatedAt, conversation.updatedAt)
        XCTAssertEqual(model.selectedConversation?.updatedAt, conversation.updatedAt)
    }

    /// A press that leaves the choice as it was writes nothing: a store that
    /// refuses every write is not asked. One that changes it is.
    func testAPressThatChangesNothingWritesNothing() async throws {
        let store = RefusingStore()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily, store: store)
        let id = try XCTUnwrap(model.selectedConversationID)
        store.refusesConversationSaves = true
        model.setTools(on: true, for: id)
        model.setServer(3, picked: false, for: id)
        XCTAssertNil(model.lastError, "a press that changed nothing wrote the conversation")
        model.setServer(3, picked: true, for: id)
        XCTAssertEqual(model.lastError, "the store refused", "a press that changed the choice wrote nothing")
    }

    /// The panel's tools Section is the master switch, then the Mac's
    /// servers in its order.
    func testThePanelRowTitlesAreTheMacsServers() {
        let menu = ToolsMenu(choice: ToolChoice(picked: [3], seen: [3, 9]), offered: [tavily, files])
        XCTAssertEqual(ToolsMenu.panelRowTitles(menu), ["Tools, 1 server", "tavily", "fs"])
    }
}
