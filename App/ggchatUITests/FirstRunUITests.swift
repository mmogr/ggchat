import XCTest

/// Drives the real app the way a first-time user does: add a provider, start
/// a conversation, send a message, watch the reply stream in.
///
/// The mock run is hermetic and always runs. The live run does the same thing
/// against the server ``LiveServer`` resolves -- the one named by
/// `GGCHAT_LIVE_BASE_URL`, or the default loopback when something is
/// listening there -- and skips when there is neither, so CI is unaffected
/// and a developer with gglib running gets the real thing.
final class FirstRunUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The claim from the handoff: a first-time user is streaming in under a
    /// minute, touching nothing but the buttons in front of them.
    @MainActor
    func testFirstRunWithTheMockProvider() throws {
        try runFirstRun(live: nil)
    }

    /// The same walk, against a real OpenAI-compatible server, carrying the
    /// key that server wants. Typing no key, which is what this did, could
    /// only ever pass against a gglib that enforces none.
    @MainActor
    func testFirstRunAgainstAServerOnThisMachine() throws {
        guard let live = LiveServer.resolve() else { throw XCTSkip(LiveServer.absenceReason) }
        try runFirstRun(live: live)
    }

    /// Launches a fresh app and walks it. `XCUIApplication` is main-actor
    /// bound, so the whole walk is, and there is no `setUp` override to
    /// disagree about isolation.
    @MainActor
    private func runFirstRun(live: LiveServer?) throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ggchat-reset", "YES"]
        app.launch()
        XCTContext.runActivity(named: "provider: \(live?.baseURL ?? "the DEBUG mock")") { _ in }
        let suffix = live == nil ? "mock" : "live"

        // 1. The first screen offers a way in.
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30), "first run offers no way to add a provider")
        addProvider.tap()
        attach(name: "01-add-provider-\(suffix)")

        // 2. Add the provider.
        if let live {
            let address = app.textFields["provider-address"].firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 10), "the address field is not reachable")
            address.tap()
            address.typeText(live.baseURL)
            typeAPIKey(live.apiKey, in: app)
            XCTAssertTrue(app.buttons["Add"].firstMatch.isEnabled, "a valid address left the Add button disabled")
            submitProviderForm(in: app)
        } else {
            // The mock lives on the providers list, one hop away.
            app.buttons["Cancel"].firstMatch.tap()
            app.buttons["Providers"].firstMatch.tap()
            let mock = app.buttons["Add mock provider"].firstMatch
            XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
            mock.tap()
            app.buttons["Done"].firstMatch.tap()
        }

        // 3. Start a conversation. The tap is retried through whatever the
        // system put on top: having typed a key into a `SecureField`, iOS
        // offers to save it once the sheet closes, and that offer swallows
        // the tap underneath it.
        let newConversation = app.buttons["New conversation"].firstMatch
        XCTAssertTrue(newConversation.waitForExistence(timeout: 10), "no way to start a conversation")

        // 4. The pill names the model that was actually listed, so a live run
        // cannot pass by quietly falling back to the mock.
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model, '")).firstMatch
        XCTAssertTrue(tap(newConversation, untilExists: pill), "the model pill never appeared")
        if live == nil {
            XCTAssertEqual(pill.label, "Model, mock-27b")
        } else {
            XCTAssertNotEqual(pill.label, "Model, mock-27b", "a live run fell back to the mock provider")
            XCTAssertNotEqual(pill.label, "Model, Choose a model", "the live server listed no models")
        }
        attach(name: "02-empty-conversation-\(suffix)")

        // 5. Send a message.
        let composer = app.textViews["composer"].firstMatch
        let field = composer.exists ? composer : app.textFields["composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "the composer never appeared")
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText("Say hello in three words.")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled, "the send button stays disabled with a message typed")
        send.tap()

        // 6. The question lands in the transcript and a reply streams in.
        XCTAssertTrue(
            app.staticTexts["Say hello in three words."].waitForExistence(timeout: 10),
            "the question never appeared in the transcript")
        XCTAssertTrue(
            app.staticTexts["ASSISTANT"].firstMatch.waitForExistence(timeout: 120), "no reply arrived")
        attach(name: "03-streaming-\(suffix)")

        // 7. It finishes: the stop button turns back into send.
        wait(
            for: [expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.buttons["Send"])],
            timeout: 180)
        attach(name: "04-reply-complete-\(suffix)")
    }

    @MainActor
    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
