import XCTest

/// The model browser, walked on the DEBUG mock engine and its library:
/// `-ggchat-mock-engine no-models` adds This iPhone at launch with nothing
/// installed, so a conversation on it has an empty model list, which is the
/// way in a walk can reach. The library's verdicts are fixed, one of each,
/// so the walk reads every chip. Part of the gallery, so the legs that draw
/// it dark and in increased contrast draw the browser too.
///
/// The sheets here close with Done, which no sweep reaches for, so the waits
/// may sweep.
extension ScreenGalleryUITests {
    private static let phoneRepo = "mock/phone-1.7b-GGUF"

    /// An iPhone with no model on it says so in the model list and offers to
    /// find one, and that opens the browser on what suits this iPhone, saying
    /// when it read the device.
    @MainActor
    func testAnEmptyPhoneOffersToFindAModel() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-engine", "no-models"])
        let suggestion = openBrowser(in: app)
        XCTAssertTrue(
            labelled(containing: "Fits · 16K", in: app).waitForExistence(timeout: 10),
            "the suggestion does not say whether it fits: \(suggestion.label)")
        let checked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Memory checked at"))
            .firstMatch
        XCTAssertTrue(checked.waitForExistence(timeout: 10), "the browser does not say when it read this iPhone")

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "the browser offers no Done")
        done.tap()
        XCTAssertTrue(checked.waitForNonExistence(timeout: 10), "the browser did not close after Done")
    }

    /// A repository's page has a row for each quantization with its size and
    /// a chip saying whether it fits; the one too big for this iPhone cannot
    /// be downloaded, one gglib cannot judge yet can, and Why says why in
    /// words. The page is the README's picture of the browser.
    @MainActor
    func testABrowsedModelSaysWhetherItFits() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-engine", "no-models"])
        let suggestion = openBrowser(in: app)
        let fits = app.buttons["Download, Q4_K_M"].firstMatch
        XCTAssertTrue(tap(suggestion, untilExists: fits), "the suggestion did not open its repository")

        for words in ["Fits · 16K", "Short context · 4K", "Too big for this iPhone", "Can't tell yet"] {
            XCTAssertTrue(
                labelled(containing: words, in: app).waitForExistence(timeout: 10), "no quantization reads \(words)")
        }
        XCTAssertTrue(fits.isEnabled, "a quantization that fits cannot be downloaded")
        XCTAssertFalse(
            app.buttons["Download, F16"].firstMatch.isEnabled,
            "a quantization too big for this iPhone can be downloaded")
        XCTAssertTrue(
            app.buttons["Download, IQ2_XS"].firstMatch.isEnabled,
            "a quantization gglib cannot judge yet cannot be downloaded")
        attach(app, name: "on-device-browser")

        let why = app.buttons["Why, Q8_0"].firstMatch
        let verdict = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "It fits only with a short context")
        ).firstMatch
        XCTAssertTrue(tap(why, untilExists: verdict), "Why did not say why the short context")
        // The sheet opens at its medium height, where its last lines sit
        // below the fold and a List leaves out the rows it does not show. On
        // an iPad the browser is a card in the middle of the screen and the
        // sheet opens inside it, too short for a flick to carry it past the
        // fold, so it springs back. The walk drags the sheet's grabber to the
        // top of the screen and lets go there, which leaves it at full height.
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 10), "the Why sheet has no grabber")
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        let lines = [
            ("The weights take", "what the weights take"),
            ("This iPhone gives a model", "what this iPhone gives a model"),
        ]
        for (words, what) in lines {
            let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", words)).firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 10), "the Why sheet does not say \(what)")
        }
        attach(app, name: "on-device-why")
    }

    /// Opens a conversation on This iPhone, its empty model list, and Find a
    /// model…, and returns the browser's suggestion of the phone's
    /// repository once it is there.
    @MainActor
    private func openBrowser(in app: XCUIApplication) -> XCUIElement {
        let pill = openConversation(in: app)
        XCTAssertTrue(pill.label.hasSuffix("Choose a model"), "an iPhone with no model names one: \(pill.label)")
        let find = app.buttons["Find a model…"].firstMatch
        XCTAssertTrue(tap(pill, untilExists: find), "an iPhone with no model did not offer to find one")
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.phoneRepo)).firstMatch
        XCTAssertTrue(tap(find, untilExists: suggestion), "Find a model… did not open the browser on a suggestion")
        return suggestion
    }

    /// Whatever carries `words` in its label: a chip on its own, or a row
    /// whose label takes in the chip's.
    @MainActor
    private func labelled(containing words: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
