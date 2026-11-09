import XCTest

/// The context ring, walked on the DEBUG mock, which reports a context size
/// beside its counts as gglib does: no ring before the first reply, a ring
/// at the trailing end of the model's row once one finishes, which stays
/// where it is while the model list is open, and a bubble over it that says
/// the counts and closes with a tap outside it. The same mock lists a model
/// that thinks and is not gglib, so the walk also finds no Thinking switch.
final class ContextRingUITests: XCTestCase {
    @MainActor
    func testAReplyRaisesTheRingAndItsBubbleSaysTheCounts() {
        let app = launchFreshApp()
        openProviderForm(in: app)
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

        // The mock's list, read by now, names mock-27b as one that thinks,
        // but a mock added by address is not gglib: no Thinking switch.
        let thinking = NSPredicate(format: "identifier == 'thinking'")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(thinking).firstMatch.exists,
            "a server that is not gglib has a Thinking switch")

        let counts = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS ' tokens (' AND label ENDSWITH 'after the last finished reply.'")
        ).firstMatch
        XCTAssertTrue(tap(ring, untilExists: counts), "the ring's bubble never said the counts")
        // A bubble, not a sheet: it is narrower than the window.
        XCTAssertLessThan(
            counts.frame.width, app.windows.firstMatch.frame.width - 40, "the counts opened as a sheet, not a bubble")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "context-bubble"
        shot.lifetime = .keepAlways
        add(shot)

        // Outside the bubble: the system's own region for that, or failing
        // it the top of the window, well away from the ring at the bottom.
        let outside = app.otherElements["PopoverDismissRegion"].firstMatch
        if outside.exists {
            outside.tap()
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
        XCTAssertTrue(counts.waitForNonExistence(timeout: 10), "the bubble did not close on a tap outside it")
        XCTAssertTrue(ring.exists, "the ring went with its bubble")
    }
}
