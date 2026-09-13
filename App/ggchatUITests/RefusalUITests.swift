import XCTest

/// A request refused before its first token: the sentence, the line about
/// where to look, what to do about it, and Retry, under the question, and all
/// of it still there after a relaunch.
///
/// The refusing mock is the DEBUG build's. Every chat request it gets is
/// refused before a token, with the code and the sentence modelpipe's edge wrote to a
/// phone the serving machine had forgotten. On 2026-09-12 that phone drew
/// nothing at all.
final class RefusalUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    func testARefusalIsDrawnUnderTheQuestionAndSurvivesARelaunch() {
        app = launchFreshApp()
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30), "first run offers no way to add a provider")
        addProvider.tap()
        // The mocks live on the providers list, one hop away.
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let refusing = app.buttons["Add refusing mock provider"].firstMatch
        XCTAssertTrue(refusing.waitForExistence(timeout: 10), "DEBUG builds offer a refusing mock provider")
        refusing.tap()
        app.buttons["Done"].firstMatch.tap()

        openConversation(in: app)
        let field = composer(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 15), "the composer never appeared")
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText("Anyone there?")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled, "the send button stays disabled with a message typed")
        send.tap()

        let sentence = text(containing: "invalid or missing bearer token")
        XCTAssertTrue(sentence.waitForExistence(timeout: 15), "the refusal drew nothing under the question")
        assertTheRestOfTheRefusalIsThere()
        attach(name: "refusal-under-the-question")

        // Kept with the question, so a relaunch finds it where it was left.
        app.terminate()
        app.launchArguments = []
        app.launch()
        if !sentence.waitForExistence(timeout: 10) {
            // A phone can open on the list instead. The conversation is its
            // only row.
            XCTAssertTrue(
                tap(app.cells.firstMatch, untilExists: sentence), "the refusal did not survive a relaunch")
        }
        assertTheRestOfTheRefusalIsThere()
        attach(name: "refusal-after-a-relaunch")
    }

    @MainActor
    private func assertTheRestOfTheRefusalIsThere(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            text(containing: "did not accept the key this app sent").waitForExistence(timeout: 5),
            "the line about the key is missing", file: file, line: line)
        XCTAssertTrue(
            text(containing: "Check the API key under Providers").exists,
            "the provider's advice is missing", file: file, line: line)
        XCTAssertTrue(app.buttons["Retry"].firstMatch.exists, "there is no way to ask again", file: file, line: line)
    }

    @MainActor
    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    @MainActor
    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
