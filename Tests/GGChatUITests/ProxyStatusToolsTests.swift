import GGChatCore
import XCTest

@testable import GGChatUI

/// The server-status sheet lists the MCP servers a paired Mac offers, read
/// from its answer about drawing, and nothing where none are offered.
@MainActor
final class ProxyStatusToolsTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    /// The names of the views a view is built from that start with one of
    /// `names`, in the order it draws them. A view found is not looked into.
    private func drawn(_ names: [String], in value: Any, depth: Int = 0) -> [String] {
        let name = String(describing: type(of: value))
        if let found = names.first(where: name.hasPrefix) { return [found] }
        guard depth < 40 else { return [] }
        return Mirror(reflecting: value).children.flatMap { drawn(names, in: $0.value, depth: depth + 1) }
    }

    /// How many rows a view's first `ForEach` draws, or nil when it has
    /// none.
    private func rows(in value: Any, depth: Int = 0) -> Int? {
        if String(describing: type(of: value)).hasPrefix("ForEach") {
            return Mirror(reflecting: value).children.first { $0.label == "data" }
                .map { Mirror(reflecting: $0.value).children.count }
        }
        guard depth < 40 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = rows(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    /// A Mac that names servers has them listed in its order, in a section
    /// of their own. One that names none, one from before the list, one not
    /// heard from and a gglib reached by address list none and draw no
    /// section.
    func testTheSheetListsTheServersAMacOffersAndNothingWhereNoneAre() async throws {
        let servers = [OfferedServer(id: 3, name: "Tavily Web Search"), OfferedServer(id: 9, name: "fs")]
        let offers = Drawing(available: false, code: "drawing_unavailable", mcpServers: servers)
        let (model, config) = try await DrawingRunTests.makeModel(behind: hub(), drawing: offers)
        XCTAssertEqual(model.toolsOffered(by: config), servers)
        let section = ToolsOfferedSection(servers: model.toolsOffered(by: config))
        XCTAssertEqual(drawn(["Section"], in: section.body), ["Section"])
        XCTAssertEqual(rows(in: section.body), 2, "a server was not listed")

        let none = Drawing(available: true, model: "flux-dev", mcpServers: [])
        for drawing in [none, DrawingRunTests.can, nil] {
            let (quiet, home) = try await DrawingRunTests.makeModel(behind: hub(), drawing: drawing)
            XCTAssertEqual(quiet.toolsOffered(by: home), [], String(describing: drawing))
        }
        let (byAddress, direct) = try await Runs.makeModel(behind: hub(), direct: true)
        byAddress.drawings[direct.id] = offers
        XCTAssertEqual(byAddress.toolsOffered(by: direct), [], "a gglib reached by address listed servers")
        XCTAssertEqual(drawn(["Section"], in: ToolsOfferedSection(servers: []).body), [])
    }
}
