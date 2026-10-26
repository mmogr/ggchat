import XCTest

/// The wrench, walked on the DEBUG mock pipe told to say it opens one MCP
/// server, tavily, id 3. A new conversation's wrench says no server is
/// picked and that new tools are on offer; tavily is picked from its menu,
/// and the wrench then says one server and no longer that anything is new.
///
/// In an iPhone Duo's bar the menu's rows lose their identifiers and the
/// wrench its own while the menu is open, so a row is found by its name
/// too, and the wrench is read once the pick has closed the menu there; on
/// an iPhone the menu stays open and the wrench can be read under it.
final class ToolsMenuUITests: XCTestCase {
    @MainActor
    func testAServerIsPickedFromTheWrenchAndTheBadgeClears() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-mcp-servers", "3:tavily"])
        openProviderForm(in: app)
        let ticket = choosePipe(in: app)
        // modelpipe's normative vector 1; the form refuses anything shorter.
        enter("pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na", into: ticket)
        let token = app.secureTextFields["provider-token"].firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        enter("a-token", into: token)
        clearingThePasswordManagerPrompt(in: app) {
            submitProviderForm(in: app)
        }
        openConversation(in: app)

        // The wrench comes with the Mac's answer, once the pipe is up.
        let wrench = app.descendants(matching: .any).matching(identifier: "tools").firstMatch
        XCTAssertTrue(wrench.waitForExistence(timeout: 60), "a Mac that opens a server has no wrench")
        XCTAssertEqual(
            wrench.label, "Tools, none picked, new tools available",
            "a new conversation's wrench does not say it picks none and has new tools on offer")

        XCTAssertTrue(waitUntilHittable(wrench, timeout: 15), "the wrench cannot be pressed")
        wrench.tap()
        let tavily = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "tools-server-3", "tavily")
        ).firstMatch
        XCTAssertTrue(tavily.waitForExistence(timeout: 10), "the wrench's menu has no row for tavily")
        tavily.tap()

        let picked = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Tools, 1 server"), object: wrench)
        XCTAssertEqual(
            XCTWaiter().wait(for: [picked], timeout: 10), .completed,
            "picking tavily did not leave the wrench saying one server and nothing new")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tools-picked"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
