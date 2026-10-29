import XCTest

/// The provider that runs on this iPhone's own engine, walked on the DEBUG
/// mock engine: `-ggchat-mock-engine ready` gives the app the mock and adds
/// "This iPhone" at launch, as "Add mock provider" adds a server for the
/// other walks. Its row says where it runs, a conversation on it needs no
/// form and no dial, and a reply raises the ring from the context the
/// engine loaded its model with. There is no Draw switch. The status pill
/// beside the model says how the model is: not loaded until the first send,
/// which loads it, and too big once the engine has refused it as that.
///
/// The sheets here close with Done, which no sweep reaches for, so the waits
/// may sweep.
final class OnDeviceUITests: XCTestCase {
    @MainActor
    func testAReplyOnThisIPhoneRaisesTheRing() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-engine", "ready"])

        // Added at launch, and listed as running here.
        let providers = app.buttons["Providers"].firstMatch
        XCTAssertTrue(waitUntilHittable(providers, timeout: 30), "no way to the providers")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'On this iPhone'")).firstMatch
        XCTAssertTrue(tap(providers, untilExists: row), "This iPhone was not added at launch")
        XCTAssertTrue(row.label.hasPrefix("This iPhone"), "the row reads \"\(row.label)\"")
        app.buttons["Done"].firstMatch.tap()

        let pill = openConversation(in: app)
        let model = app.buttons.matching(NSPredicate(format: "label CONTAINS 'mock-phone-1.7b'")).firstMatch
        XCTAssertTrue(
            model.waitForExistence(timeout: 30), "the engine's model is not the conversation's: \(pill.label)")

        let ring = app.buttons["Context"].firstMatch
        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        XCTAssertFalse(ring.exists, "a conversation with no reply shows a ring")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "draw").firstMatch.exists,
            "an engine that draws nothing has a Draw switch")
        field.typeText("Hello")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        XCTAssertTrue(ring.waitForExistence(timeout: 120), "a reply on this iPhone raised no ring")
        let spoken = (ring.value as? String) ?? ""
        XCTAssertTrue(spoken.hasSuffix("percent of context used"), "VoiceOver hears \"\(spoken)\" for the ring")

        // The engine said the context it loaded, 4096, so the sheet reads
        // it, grouped as the locale groups digits.
        let size = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS ' tokens (' AND label CONTAINS '096 tokens'")
        ).firstMatch
        XCTAssertTrue(tap(ring, untilExists: size), "the ring's sheet does not read the engine's context")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "on-device-ring"
        shot.lifetime = .keepAlways
        add(shot)
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "the sheet offers no Done")
        done.tap()
        XCTAssertTrue(size.waitForNonExistence(timeout: 10), "the sheet did not close after Done")
    }

    /// The model is not loaded when the conversation opens; the first send
    /// loads it, the pill walking from loading to ready, and the reply
    /// follows. `slow` loads in ten steps, 400 ms apart, so the walk can
    /// read the pill while it loads.
    @MainActor
    func testAFirstSendLoadsTheModelThenReplies() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-engine", "slow"])
        let pill = openConversation(in: app)
        let model = app.buttons.matching(NSPredicate(format: "label CONTAINS 'mock-phone-1.7b'")).firstMatch
        XCTAssertTrue(
            model.waitForExistence(timeout: 30), "the engine's model is not the conversation's: \(pill.label)")
        XCTAssertTrue(
            app.buttons["Model Not loaded"].firstMatch.waitForExistence(timeout: 30),
            "the pill does not say the model is not loaded before anything was sent")

        send("Hello", in: app)
        let loading = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model Loading '")).firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 30), "the pill never said the model was loading")
        XCTAssertTrue(
            app.buttons["Model Ready"].firstMatch.waitForExistence(timeout: 60),
            "the pill never said the model was ready")
        XCTAssertTrue(
            app.buttons["Context"].firstMatch.waitForExistence(timeout: 120), "no reply followed the model's load")
    }

    /// A model the engine refuses as too big for this iPhone: the question is
    /// refused, the pill says "Too big", and pressing it opens the model
    /// browser, where a smaller one can be found.
    @MainActor
    func testATooBigModelSaysSoInThePill() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-engine", "too-big"])
        let pill = openConversation(in: app)
        let model = app.buttons.matching(NSPredicate(format: "label CONTAINS 'mock-phone-1.7b'")).firstMatch
        XCTAssertTrue(
            model.waitForExistence(timeout: 30), "the engine's model is not the conversation's: \(pill.label)")

        send("Hello", in: app)
        let tooBig = app.buttons["Model Too big"].firstMatch
        XCTAssertTrue(tooBig.waitForExistence(timeout: 60), "the pill does not say the model is too big")
        let checked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Memory checked at"))
            .firstMatch
        XCTAssertTrue(tap(tooBig, untilExists: checked), "Too big did not open the model browser")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "the browser offers no Done")
        done.tap()
        XCTAssertTrue(checked.waitForNonExistence(timeout: 10), "the browser did not close after Done")
    }

    /// Types `text` into the composer and sends it.
    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        let field = composer(in: app)
        XCTAssertTrue(caret(in: field, of: app), "the composer never took the caret")
        field.typeText(text)
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no Send")
        send.tap()
    }
}
