import GGChatCore
import XCTest

@testable import GGChatUI

/// The model list's chips and search, over sections made by hand:
/// `ModelList.make` is the whole of it, and the view only shows what it
/// leaves.
final class ModelListFilterTests: XCTestCase {
    private func provider(_ name: String) -> ProviderConfig {
        ProviderConfig(name: name, kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:1/v1")!))
    }

    private func section(
        _ config: ProviderConfig, _ models: [(String, String?)], listed: Bool = true
    )
        -> ModelListSection
    {
        ModelListSection(
            provider: config, state: nil,
            rows: models.map { ModelListRow(modelID: $0.0, detail: $0.1, isCurrent: false) }, isListed: listed,
            isStale: false, moves: true)
    }

    /// One provider has no chips and ignores a filter; with two or more,
    /// All comes first and then a chip for each, a filter shows that
    /// provider's section alone, and one naming a provider no longer there
    /// reads as All, a section with nothing listed included.
    func testChipsAppearWithTwoProvidersAndFilterToOne() {
        let phone = provider("This iPhone")
        let home = provider("home")
        let gone = provider("gone")
        let one = [section(phone, [("Qwen3.5-4B", "4B · Q6_K_XL")])]
        XCTAssertEqual(ModelList.make(one, filter: phone.id, query: "").chips, [])
        XCTAssertNil(ModelList.make(one, filter: phone.id, query: "").filter)

        let all = one + [section(home, [("gpt-oss-20b", "20B · MXFP4")]), section(gone, [], listed: false)]
        let filtered = ModelList.make(all, filter: home.id, query: "")
        XCTAssertEqual(filtered.chips.map(\.name), ["This iPhone", "home", "gone"])
        XCTAssertEqual(filtered.filter, home.id)
        XCTAssertEqual(filtered.sections.map(\.provider.name), ["home"])

        let stale = ModelList.make(all, filter: UUID(), query: "")
        XCTAssertNil(stale.filter)
        XCTAssertEqual(stale.sections.map(\.provider.name), ["This iPhone", "home", "gone"])
    }

    /// A search matches a model's id or its line, ignoring case and the
    /// space around it, within the filter; a section with no match is left
    /// out, and finding nothing is said.
    func testASearchMatchesTheIdOrTheLineWithinTheFilter() {
        let phone = provider("This iPhone")
        let home = provider("home")
        let all = [
            section(phone, [("Qwen3.5-4B", "4B · Q6_K_XL"), ("Qwen3-0.6B", "0.6B · Q4_K_M")]),
            section(home, [("gpt-oss-20b", "20B · MXFP4"), ("Qwen3-4B", "4B · Q8_0")]),
        ]
        let byID = ModelList.make(all, filter: nil, query: "  qwen3-")
        XCTAssertEqual(byID.query, "qwen3-")
        XCTAssertEqual(byID.sections.flatMap(\.rows).map(\.modelID), ["Qwen3-0.6B", "Qwen3-4B"])

        let byLine = ModelList.make(all, filter: nil, query: "mxfp4")
        XCTAssertEqual(byLine.sections.map(\.provider.name), ["home"])
        XCTAssertEqual(byLine.sections.flatMap(\.rows).map(\.modelID), ["gpt-oss-20b"])

        let within = ModelList.make(all, filter: phone.id, query: "4b")
        XCTAssertEqual(within.sections.flatMap(\.rows).map(\.modelID), ["Qwen3.5-4B"])

        XCTAssertTrue(ModelList.make(all, filter: nil, query: "llama").foundNothing)
        XCTAssertFalse(ModelList.make(all, filter: nil, query: " ").foundNothing)
    }

    /// The search is offered once the providers list more than eight models
    /// between them, counted before any filter.
    func testASearchIsOfferedPastEightModels() {
        let phone = provider("This iPhone")
        let home = provider("home")
        let eight = [
            section(phone, (1...4).map { ("phone-\($0)", nil) }),
            section(home, (1...4).map { ("home-\($0)", nil) }),
        ]
        XCTAssertFalse(ModelList.make(eight, filter: nil, query: "").offersSearch)
        let nine = eight + [section(provider("server"), [("one-more", nil)])]
        XCTAssertTrue(ModelList.make(nine, filter: home.id, query: "").offersSearch)
    }

    /// The open list takes no more than six tenths of the chat's free
    /// height and leaves 190 points for the pill, the composer and a strip
    /// of the chat, to 460 at most and 96 at least: a 6.3-inch iPhone with
    /// its keyboard up, about 420 points free, gets 230, so its search stays
    /// on screen; with the keyboard down, and on an iPad, the cap.
    func testThePanelIsSizedFromTheRoomThereIs() {
        XCTAssertEqual(ModelList.panelHeight(room: 0), 460, "unmeasured")
        XCTAssertEqual(ModelList.panelHeight(room: 420), 230)
        XCTAssertEqual(ModelList.panelHeight(room: 700), 420)
        XCTAssertEqual(ModelList.panelHeight(room: 1_100), 460)
        XCTAssertEqual(ModelList.panelHeight(room: 250), 96)
        XCTAssertTrue(ModelList.pinsItsTop(height: ModelList.panelHeight(room: 420), accessible: false))
    }

    /// At an accessibility text size the list leaves 320 points for the
    /// stacked pills and the taller composer, keeps no chips, and its search
    /// and caption scroll with the rows; so do they below 200 points of
    /// list at any size, so nothing runs past the list's height.
    func testAtAnAccessibilitySizeTheListLeavesMoreAndKeepsNoChips() {
        XCTAssertEqual(ModelList.panelHeight(room: 420, accessible: true), 100)
        XCTAssertEqual(ModelList.panelHeight(room: 700, accessible: true), 380)
        XCTAssertEqual(ModelList.panelHeight(room: 350, accessible: true), 96)
        XCTAssertEqual(ModelList.panelHeight(room: 0, accessible: true), 460, "unmeasured")
        XCTAssertFalse(ModelList.pinsItsTop(height: 380, accessible: true))
        XCTAssertFalse(ModelList.pinsItsTop(height: 150, accessible: false))
        XCTAssertTrue(ModelList.pinsItsTop(height: 200, accessible: false))
    }
}
