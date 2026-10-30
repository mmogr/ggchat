import XCTest

/// gglib's own engine on a real iPhone, not the mock: `make
/// uitest-device-engine` on the owner's phone, with
/// `GGCHAT_LIVE_ENGINE_MODEL` naming a model already downloaded to it as its
/// model list names it. Skipped unless that is set, so the simulator walks
/// and CI never take it; no simulator runs gglib's engine.
///
/// `-ggchat-live-engine-model` adds This iPhone at launch with that model
/// chosen. The first send loads the model, the pill reading Ready once it
/// has; the reply raises the ring from the context the engine loaded it
/// with. Going to the background puts the engine down, so coming back the
/// pill reads Not loaded, and the next send loads the model again.
final class OnDeviceLiveUITests: XCTestCase {
    @MainActor
    func testAReplyOnThisIPhoneComesFromGglibsOwnEngine() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let model = environment["GGCHAT_LIVE_ENGINE_MODEL"], !model.isEmpty else {
            throw XCTSkip("GGCHAT_LIVE_ENGINE_MODEL is not set; `make uitest-device-engine` sets it")
        }
        let app = launchFreshApp(arguments: ["-ggchat-live-engine-model", model])
        let pill = openConversation(in: app)
        let chosen = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", model)).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 60), "\(model) is not the conversation's: \(pill.label)")
        XCTAssertTrue(
            app.buttons["Model Not loaded"].firstMatch.waitForExistence(timeout: 60),
            "the pill does not say the model is not loaded before anything was sent")

        send("Say hello in five words.", in: app)
        let ready = app.buttons["Model Ready"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 300), "the pill never said the model was ready")
        let ring = app.buttons["Context"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 300), "a reply from gglib's engine raised no ring")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "on-device-reply"
        shot.lifetime = .keepAlways
        add(shot)
        let size = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' tokens ('")).firstMatch
        XCTAssertTrue(tap(ring, untilExists: size), "the ring's sheet does not read the engine's context")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "the sheet offers no Done")
        done.tap()

        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackgroundSuspended, timeout: 30)
        app.activate()
        XCTAssertTrue(
            app.buttons["Model Not loaded"].firstMatch.waitForExistence(timeout: 60),
            "the engine was not put down in the background")
        send("And again.", in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 300), "the next send did not load the model again")
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
