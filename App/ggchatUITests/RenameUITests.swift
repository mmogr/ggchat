import XCTest

/// A chat kept here is renamed from its row's menu in the list, and its name
/// cleared from its title's menu over the chat, walked on the DEBUG mock.
final class RenameUITests: XCTestCase {
    @MainActor
    func testAChatIsRenamedFromItsRowAndClearedFromItsTitle() {
        let app = launchFreshApp()
        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        let pill = openConversation(in: app)

        // The list is one screen back on an iPhone and a column beside the
        // chat on an iPad, where going back would hit the sidebar toggle.
        let row = app.cells.containing(NSPredicate(format: "label BEGINSWITH 'New conversation, '")).firstMatch
        if !waitUntilHittable(row, timeout: 5) {
            XCTAssertTrue(
                tap(app.navigationBars.buttons.element(boundBy: 0), untilExists: row),
                "going back did not reach the conversation list")
        }
        let rename = app.buttons["Rename"].firstMatch
        XCTAssertTrue(press(row, untilExists: rename), "the row's menu has no Rename")
        rename.tap()
        name(as: "Kyoto in spring", offered: "New conversation", in: app)
        let renamed = app.cells.containing(NSPredicate(format: "label BEGINSWITH 'Kyoto in spring, '")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 10), "the list does not call the chat by its name")

        XCTAssertTrue(tap(renamed, untilExists: pill), "the renamed chat never opened")
        let title = app.navigationBars.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Kyoto in spring'")).firstMatch
        XCTAssertTrue(tap(title, untilExists: rename), "the chat's title has no Rename")
        rename.tap()
        name(as: "", offered: "Kyoto in spring", in: app)
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "a cleared name is still the chat's title")
    }

    /// Checks the rename field offers the title shown, `offered`, then
    /// replaces it with `text` and confirms it. Tapped directly: the walks'
    /// sweep for prompts taps any Cancel, and this one's would close the
    /// field.
    @MainActor
    private func name(as text: String, offered: String, in app: XCUIApplication) {
        let alert = app.alerts["Rename chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Rename opened no field")
        let field = alert.textFields.firstMatch
        XCTAssertEqual(field.value as? String, offered, "the field did not offer the title shown")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: offered.count + 4) + text)
        alert.buttons["Rename"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "Rename did not close the field")
    }
}
