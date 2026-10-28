import XCTest

/// The composer while a reply runs, walked on the DEBUG mock slowed to a
/// word every 300 ms: it takes the caret and the next message mid-reply,
/// keeps that message unsent until the reply ends, and sends it then.
final class TypingDuringAReplyUITests: XCTestCase {
    @MainActor
    func testTheNextMessageIsWrittenWhileAReplyRuns() {
        let app = launchFreshApp(arguments: ["-ggchat-slow-mock", "YES"])
        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        openConversation(in: app)

        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText("First question")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        let stop = app.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "the reply never started")

        // Asked again: the field may be a text view or a text field by now.
        let during = composer(in: app)
        XCTAssertTrue(during.isEnabled, "the composer is shut while a reply runs")
        XCTAssertTrue(caret(in: during, of: app), "the composer took no caret while a reply ran")
        during.typeText("Second question")
        XCTAssertTrue(stop.exists, "the reply ended before the next message was written")
        XCTAssertFalse(send.exists, "Send came back while the reply still ran")

        XCTAssertTrue(send.waitForExistence(timeout: 120), "the reply never finished")
        let written = app.scrollViews.staticTexts["Second question"].firstMatch
        XCTAssertFalse(written.exists, "the message written during the reply was sent before it ended")
        XCTAssertEqual(
            composer(in: app).value as? String, "Second question", "the message written during the reply was lost")
        send.tap()
        XCTAssertTrue(
            written.waitForExistence(timeout: 10), "the message written during the reply was not sent after it")
    }
}
