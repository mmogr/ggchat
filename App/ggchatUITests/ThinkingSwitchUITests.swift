import XCTest

/// The Thinking switch, walked on the DEBUG mock pipe: the one mock the app
/// takes for gglib, whose first model is listed as one that thinks. The
/// switch is in the conversation's top bar and says "On"; switched off it
/// says "Off" and the reply has no reasoning row; switched back on, the next
/// reply has one.
///
/// Off goes first, so the reply checked for having no reasoning is the only
/// one on screen, and the one checked for having it is the newest, at the
/// bottom: a row scrolled out of a lazy stack is not in the tree either way.
final class ThinkingSwitchUITests: XCTestCase {
    @MainActor
    func testTurningThinkingOffDropsTheReasoningRow() {
        let app = launchFreshApp()
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30), "first run offers no way to add a provider")
        addProvider.tap()
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

        // The switch comes with the pipe: its models are listed once it is up.
        let toggle = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Thinking' AND (value == 'On' OR value == 'Off')")
        ).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 60), "a model listed as thinking has no Thinking switch")
        XCTAssertEqual(toggle.value as? String, "On", "a new conversation's switch is not on")
        XCTAssertTrue(app.buttons["System prompt"].firstMatch.exists, "the switch took the system prompt's place")

        XCTAssertTrue(waitUntilHittable(toggle, timeout: 15), "the switch cannot be pressed")
        toggle.tap()
        XCTAssertTrue(says("Off", toggle), "pressing the switch did not turn it off")

        let reasoning = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Reasoning, '"))
        send("Hello", in: app)
        XCTAssertTrue(
            app.staticTexts["ASSISTANT"].firstMatch.waitForExistence(timeout: 60), "no reply arrived with thinking off")
        XCTAssertTrue(app.buttons["Send"].firstMatch.waitForExistence(timeout: 60), "the reply never finished")
        XCTAssertFalse(reasoning.firstMatch.exists, "a reply asked for with thinking off has a reasoning row")
        XCTAssertEqual(toggle.value as? String, "Off", "the switch flipped back after a reply")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "thinking-off"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(waitUntilHittable(toggle, timeout: 15), "the switch cannot be pressed again")
        toggle.tap()
        XCTAssertTrue(says("On", toggle), "pressing the switch did not turn it back on")
        send("Again", in: app)
        XCTAssertTrue(
            reasoning.firstMatch.waitForExistence(timeout: 60),
            "a reply asked for with thinking on has no reasoning row")
    }

    /// Whether the switch comes to say `value`.
    @MainActor
    private func says(_ value: String, _ toggle: XCUIElement) -> Bool {
        let said = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        return XCTWaiter().wait(for: [said], timeout: 10) == .completed
    }

    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText(text)
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), "the question never appeared")
    }
}
