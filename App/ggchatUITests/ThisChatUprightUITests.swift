import XCTest

/// An open iPhone Duo held upright: the list beside the chat, and the chat's
/// own controls in its panel, which takes the list's place, rather than
/// crowded into a top bar a third of the screen wide. `simctl` cannot open
/// the simulator, so the walk runs only where the window is already an open
/// Duo held upright, opened by hand in Xcode's Device Hub, and is skipped
/// elsewhere.
final class ThisChatUprightUITests: XCTestCase {
    @MainActor
    func testAnUprightOpenDuoKeepsTheChatsControlsInItsPanel() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "an iPad keeps the system's split view")
        let app = launchFreshApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        try XCTSkipUnless(
            window.frame.height > window.frame.width && window.frame.width >= 600,
            "this simulator is not an open Duo held upright")

        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10))
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        openConversation(in: app)
        let field = composer(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the conversation has no composer")

        XCTAssertFalse(
            app.buttons["system-prompt"].firstMatch.exists, "the chat's top bar kept a control the panel holds")
        let compose = app.buttons["New conversation"].firstMatch
        let panelButton = app.buttons["this-chat"].firstMatch
        XCTAssertTrue(panelButton.waitForExistence(timeout: 10), "the chat's top bar has no panel button")

        let promptRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'System prompt'")).firstMatch
        XCTAssertTrue(tap(panelButton, untilExists: promptRow), "the panel never took the list's place")
        XCTAssertLessThan(promptRow.frame.maxX, field.frame.minX + 1, "the panel is not beside the chat")
        XCTAssertFalse(compose.exists, "the list stayed with the panel up")

        XCTAssertTrue(tap(panelButton, untilExists: compose), "the panel button did not put the list back")
    }

    /// Providers opens in the chat's column, over the chat, with the list
    /// where it was; Done takes it away and the chat's draft is as it was.
    @MainActor
    func testProvidersOpenOverTheChatAndLeaveItsDraft() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "an iPad keeps the system's split view")
        let app = launchFreshApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        try XCTSkipUnless(
            window.frame.height > window.frame.width && window.frame.width >= 600,
            "this simulator is not an open Duo held upright")

        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        let providers = app.buttons["Providers"].firstMatch
        providers.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10))
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        openConversation(in: app)
        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText("Kept under")
        let column = field.frame

        XCTAssertTrue(tap(providers, untilExists: mock), "Providers did not open")
        XCTAssertGreaterThanOrEqual(mock.frame.minX, column.minX - 1, "Providers did not open in the chat's column")
        let compose = app.buttons["New conversation"].firstMatch
        XCTAssertTrue(compose.exists, "the list went when Providers opened")
        XCTAssertTrue(providers.isSelected, "the Providers button is not shown as chosen")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(mock.waitForNonExistence(timeout: 10), "Done did not take Providers away")
        XCTAssertTrue(
            ((composer(in: app).value as? String) ?? "").contains("Kept under"),
            "the draft was lost under Providers")
    }
}
