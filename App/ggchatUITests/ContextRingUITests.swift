import XCTest

/// The context ring, walked on the DEBUG mock, which reports a context size
/// beside its counts as gglib does: no ring before the first reply, a ring
/// at the trailing end of the model's row once one finishes, which stays
/// where it is while the model list is open, and a sheet that says the
/// counts and closes with Done.
///
/// The sheet's one button is titled "Done", which no sweep reaches for, so
/// the waits in here may sweep.
final class ContextRingUITests: XCTestCase {
    @MainActor
    func testAReplyRaisesTheRingAndItsSheetSaysTheCounts() {
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
        let pill = openConversation(in: app)

        let ring = app.buttons["Context"].firstMatch
        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        XCTAssertFalse(ring.exists, "a conversation with no reply shows a ring")
        field.typeText("Hello")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        XCTAssertTrue(ring.waitForExistence(timeout: 120), "a finished reply raised no ring")
        let spoken = (ring.value as? String) ?? ""
        XCTAssertTrue(spoken.hasSuffix("percent of context used"), "VoiceOver hears \"\(spoken)\" for the ring")

        // The row ends where the composer under it does. Send is the last
        // thing in the composer, its padding in from that edge, so the ring
        // ends a few points past Send and never short of it.
        XCTAssertTrue(send.waitForExistence(timeout: 10), "Send did not come back once the reply finished")
        let closed = ring.frame
        let pastSend = closed.maxX - send.frame.maxX
        XCTAssertTrue(
            (0...16).contains(pastSend),
            "the ring is not at the trailing end of the model's row: it ends \(pastSend) points past Send")

        // The pill grows into its list, and the ring stays where it was.
        let listed = app.buttons.matching(NSPredicate(format: "label CONTAINS 'mock-4b'")).firstMatch
        XCTAssertTrue(tap(pill, untilExists: listed), "the model list never opened")
        let opened = ring.frame
        XCTAssertEqual(opened.minX, closed.minX, accuracy: 1, "opening the model list moved the ring")
        XCTAssertEqual(opened.maxX, closed.maxX, accuracy: 1, "opening the model list moved the ring's far edge")
        pill.tap()
        XCTAssertTrue(listed.waitForNonExistence(timeout: 10), "the model list did not close")

        let counts = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS ' tokens (' AND label ENDSWITH 'after the last finished reply.'")
        ).firstMatch
        XCTAssertTrue(tap(ring, untilExists: counts), "the ring's sheet never said the counts")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "context-sheet"
        shot.lifetime = .keepAlways
        add(shot)

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "the sheet offers no Done")
        done.tap()
        XCTAssertTrue(counts.waitForNonExistence(timeout: 10), "the sheet did not close after Done")
        XCTAssertTrue(ring.exists, "the ring went with its sheet")
    }
}
