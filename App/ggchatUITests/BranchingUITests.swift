import XCTest

/// A reply edited from its menu opens a new branch of the conversation
/// (ADR 0010), walked on the DEBUG mock: the edit is kept as written there,
/// the switcher in the reply's header says it is the second of two, and
/// Previous opens the conversation it was made on, the reply as it was.
final class BranchingUITests: XCTestCase {
    @MainActor
    func testAnEditedReplyOpensABranchAndPreviousGoesBack() {
        let app = launchFreshApp()
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30), "first run offers no way to add a provider")
        addProvider.tap()
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        openConversation(in: app)

        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText("Plan a trip")
        app.buttons["Send"].firstMatch.tap()
        let reply = app.staticTexts["ASSISTANT"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 60), "no reply arrived")
        XCTAssertTrue(app.buttons["Send"].firstMatch.waitForExistence(timeout: 60), "the reply never finished")

        reply.press(forDuration: 1.2)
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "the reply's menu has no Edit")
        edit.tap()
        let editor = app.textViews["Reply"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Edit opened no editor")
        XCTAssertTrue(caret(in: editor, of: app), "the editor never took the caret")
        editor.typeText(" Kept as written.")
        app.buttons["Save"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Kept as written.'")).firstMatch
                .waitForExistence(timeout: 10),
            "the edited reply is not on screen")
        let second = app.buttons["Branch 2 of 2"].firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10), "the branch has no switcher at its reply")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "branch-opened"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Previous branch"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Branch 1 of 2"].firstMatch.waitForExistence(timeout: 10), "Previous opened nothing")
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Kept as written.'")).firstMatch.exists,
            "the conversation the edit was made on changed")
    }
}
