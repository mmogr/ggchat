import XCTest

/// A long chat's way back to its latest message, walked on the DEBUG mock:
/// no button while the transcript follows its replies, one once it is
/// scrolled well up, and none again after it is tapped, with the latest
/// reply on screen and the next one still followed.
final class JumpToLatestUITests: XCTestCase {
    /// The last line of every reply the mock writes.
    private let ending = NSPredicate(format: "label == 'That is all there is to it.'")

    @MainActor
    func testAChatScrolledUpOffersAWayBackToItsLatestReply() {
        let app = launchFreshApp()
        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        openConversation(in: app)

        let jump = app.buttons["jump-to-latest"].firstMatch
        // Enough replies to fill the screen twice over with the keyboard
        // down, which the scrolling up below takes away: four on a phone,
        // eight on an iPad held upright.
        let turns = max(4, Int((app.windows.firstMatch.frame.height / 180).rounded(.up)))
        for turn in 1...turns {
            send("Question \(turn)", in: app)
            XCTAssertTrue(latestEndingIsOnScreen(after: turn, in: app), "reply \(turn) was not followed to its end")
            XCTAssertFalse(jump.exists, "a transcript at its latest offers a way to it")
        }

        for _ in 0..<8 where !jump.exists {
            nudge(in: app, up: false)
        }
        XCTAssertTrue(waitUntilHittable(jump, timeout: 5), "a chat scrolled well up offers no way back")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "jump-to-latest"
        shot.lifetime = .keepAlways
        add(shot)

        jump.tap()
        XCTAssertTrue(jump.waitForNonExistence(timeout: 10), "the button stayed after taking the chat to its latest")
        XCTAssertTrue(latestEndingIsOnScreen(after: turns, in: app), "the jump did not reach the latest reply")

        send("Question \(turns + 1)", in: app)
        XCTAssertTrue(
            latestEndingIsOnScreen(after: turns + 1, in: app), "a reply after the jump was not followed to its end")
        XCTAssertFalse(jump.exists, "a transcript at its latest offers a way to it")
    }

    /// Types into the composer, sends, and returns once the reply has
    /// finished, which is when Send comes back in place of Stop.
    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText(text)
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(app.buttons["Stop"].firstMatch.waitForExistence(timeout: 10), "the reply never started")
        XCTAssertTrue(send.waitForExistence(timeout: 120), "the reply never finished")
    }

    /// The newest reply's last line can be tapped: the last one the tree
    /// lists, below the newest question in the transcript (the bar's title
    /// is the first question's), so an earlier reply left on screen by a jump
    /// that stopped short does not pass for it.
    @MainActor
    private func latestEndingIsOnScreen(after turn: Int, in app: XCUIApplication) -> Bool {
        let endings = app.staticTexts.matching(ending)
        guard endings.firstMatch.waitForExistence(timeout: 10) else { return false }
        let last = endings.element(boundBy: endings.count - 1)
        guard waitUntilHittable(last, timeout: 5) else { return false }
        let question = app.scrollViews.staticTexts["Question \(turn)"].firstMatch
        return question.exists && question.frame.minY < last.frame.minY
    }
}
