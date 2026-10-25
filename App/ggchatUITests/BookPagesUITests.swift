import XCTest

/// An open iPhone Duo on its side, half open: the list on the leading page,
/// the chat on the trailing one, and the chat's panel in the list's place.
/// No simulator can be half opened by a test, so the app is launched with
/// `-ggchat-fold YES`, which reports a fold down the middle of the window,
/// and the walk turns an iPhone on its side. Only the real Duo proves the
/// pose; this proves the pages, the panel and the draft kept across them.
final class BookPagesUITests: XCTestCase {
    @MainActor
    func testTheChatIsOnTheTrailingPageAndItsPanelOnTheLeading() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "an iPad keeps the system's split view")
        XCUIDevice.shared.orientation = .landscapeLeft
        // Upright again for the walks after this one, pass or fail.
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = launchFreshApp(arguments: ["-ggchat-fold", "YES"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        try XCTSkipIf(window.frame.width <= window.frame.height, "this simulator did not turn on its side")

        addMockProvider(in: app)
        openConversation(in: app)
        let field = composer(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the conversation has no composer")
        let middle = window.frame.midX
        XCTAssertGreaterThanOrEqual(field.frame.minX, middle - 1, "the chat is not on the trailing page")
        let compose = app.buttons["New conversation"].firstMatch
        XCTAssertLessThan(compose.frame.maxX, middle, "the list is not on the leading page")
        XCTAssertFalse(
            app.buttons["system-prompt"].firstMatch.exists, "the chat's top bar kept a control the panel holds")

        // The panel, and a prompt set from it on the leading page.
        let panelButton = app.buttons["this-chat"].firstMatch
        let promptRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'System prompt'")).firstMatch
        XCTAssertTrue(tap(panelButton, untilExists: promptRow), "the panel never took the list's place")
        let editor = app.textViews["system-prompt"].firstMatch
        XCTAssertTrue(tap(promptRow, untilExists: editor, sweeping: false), "the panel's prompt never opened")
        XCTAssertLessThan(editor.frame.maxX, middle, "the prompt did not open on the leading page")
        enter("Answer in French.", into: editor)
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(waitUntilHittable(save, timeout: 10, sweeping: false), "the prompt offers no Save")
        save.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10), "Save did not go back to the panel")
        // The row is one button, its value in its label.
        let isSet = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label ENDSWITH 'Set'"), object: promptRow)
        XCTAssertEqual(
            XCTWaiter().wait(for: [isSet], timeout: 10), .completed, "the panel does not say a prompt is set")
        attach(app, name: "book-pages-panel")

        // A draft is kept while the list goes and comes back.
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText("Kept across")
        let listButton = app.buttons["conversation-list"].firstMatch
        XCTAssertTrue(tap(listButton, untilExists: compose), "the list button did not put the list back")
        let paged = field.frame.width
        listButton.tap()
        XCTAssertTrue(compose.waitForNonExistence(timeout: 10), "the list button did not hide the list")
        // A frame cannot be waited on by predicate, so it is read until it
        // widens.
        let deadline = Date().addingTimeInterval(10)
        while field.frame.width <= paged + 100, Date() < deadline { _ = field.waitForExistence(timeout: 0.5) }
        XCTAssertGreaterThan(field.frame.width, paged + 100, "the chat did not take the screen")
        XCTAssertTrue(tap(listButton, untilExists: compose), "the list did not come back")
        XCTAssertTrue(
            ((composer(in: app).value as? String) ?? "").contains("Kept across"),
            "the draft was lost when the list went and came back")
    }

    @MainActor
    private func addMockProvider(in app: XCUIApplication) {
        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10))
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
