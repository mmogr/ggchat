import XCTest

/// The model browser, walked on the DEBUG mock engine and its library:
/// `-ggchat-mock-engine no-models` adds This iPhone at launch with nothing
/// installed, so a conversation on it has an empty model list, which offers
/// "Find a model…"; with `-ggchat-mock-engine-unadded YES` as well nothing is
/// added, a first run, whose way in is Add provider's This iPhone. The
/// library's verdicts are fixed, one of each,
/// so the walk reads every chip, and its downloads walk to done in about ten
/// seconds, a second a step, and are listed by the mock engine. Part of the
/// gallery, so the legs that draw it dark and in increased contrast draw the
/// browser too.
///
/// The sheets here close with Done, which no sweep reaches for, so the waits
/// may sweep.
extension ScreenGalleryUITests {
    /// The phone's repository as a suggestion's row names it: the model,
    /// the last part of `mock/phone-1.7b-GGUF`.
    private static let phoneModel = "phone-1.7b-GGUF"

    /// A phone with no model and no provider says This iPhone is one of the
    /// choices and offers Add provider, whose This iPhone shows the browser
    /// in place of a form: what suits this iPhone, each with a chip saying
    /// whether it fits, which opens gglib's sentence on why that one, and
    /// when it read the device. Looking adds nothing: closing it leaves
    /// first run as it was.
    @MainActor
    func testAnEmptyPhoneOffersThisIPhoneInAddProvider() {
        let app = launchFreshApp(arguments: [
            "-ggchat-mock-engine", "no-models", "-ggchat-mock-engine-unadded", "YES",
        ])
        let choices = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "a model to run on this iPhone")
        ).firstMatch
        XCTAssertTrue(choices.waitForExistence(timeout: 30), "first run does not say This iPhone is a choice")
        openProviderForm(in: app)
        let thisIPhone = app.buttons["This iPhone"].firstMatch
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.phoneModel)).firstMatch
        XCTAssertTrue(
            tap(thisIPhone, untilExists: suggestion, sweeping: false),
            "Add provider's This iPhone did not show the browser on a suggestion")
        XCTAssertFalse(app.textFields["provider-name"].exists, "This iPhone asks for a name")
        XCTAssertTrue(
            labelled(containing: "Fits · 16K", in: app).waitForExistence(timeout: 10),
            "the suggestion does not say whether it fits: \(suggestion.label)")
        let checked = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Memory checked at"))
            .firstMatch
        XCTAssertTrue(checked.waitForExistence(timeout: 10), "the browser does not say when it read this iPhone")

        // The chip beside the suggestion's link takes its own tap.
        let chip = app.buttons["fit-mock/phone-1.7b-GGUF/Q4_K_M"].firstMatch
        let rationale = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "The largest of the suggested models")
        ).firstMatch
        XCTAssertTrue(tap(chip, untilExists: rationale), "the suggestion's chip did not say why gglib suggests it")
        XCTAssertTrue(app.staticTexts["gglib suggests it"].firstMatch.exists, "the sentence is not under its heading")
        let sheetDone = app.navigationBars["Q4_K_M"].buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(sheetDone, timeout: 10), "the chip's sheet offers no Done")
        sheetDone.tap()
        XCTAssertTrue(rationale.waitForNonExistence(timeout: 10), "the chip's sheet did not close after Done")

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "This iPhone offers no Done")
        done.tap()
        XCTAssertTrue(checked.waitForNonExistence(timeout: 10), "Add provider did not close after Done")
        XCTAssertTrue(
            app.buttons["Add a provider"].firstMatch.waitForExistence(timeout: 10),
            "looking at the browser added a provider")
    }

    /// A repository's page has a row for each quantization with its size and
    /// a chip saying whether it fits; the one too big for this iPhone offers
    /// no download, one gglib cannot judge yet does, and a chip, pressed,
    /// says how gglib judged it in words. The page is the README's picture
    /// of the browser.
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
            app.buttons["Download, F16"].firstMatch.exists, "a quantization too big for this iPhone can be downloaded")
        XCTAssertTrue(
            app.buttons["Download, IQ2_XS"].firstMatch.isEnabled,
            "a quantization gglib cannot judge yet cannot be downloaded")
        attach(app, name: "on-device-browser")

        let chip = app.buttons["fit-Q8_0"].firstMatch
        let verdict = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "It fits only with a short context")
        ).firstMatch
        XCTAssertTrue(tap(chip, untilExists: verdict), "the chip did not say why the short context")
        // The sheet opens at its medium height, where its last lines sit
        // below the fold and a List leaves out the rows it does not show. On
        // an iPad the browser is a card in the middle of the screen and the
        // sheet opens inside it, too short for a flick to carry it past the
        // fold, so it springs back. The walk drags the sheet's grabber to the
        // top of the screen and lets go there, which leaves it at full height.
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 10), "the chip's sheet has no grabber")
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        let lines = [
            ("The weights take", "what the weights take"),
            ("This iPhone gives a model", "what this iPhone gives a model"),
        ]
        for (words, what) in lines {
            let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", words)).firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 10), "the chip's sheet does not say \(what)")
        }
        attach(app, name: "on-device-why")
    }

    /// A download fills its bar, says how much of how much has come with
    /// Cancel beside it, and once it is done the model joins the list the
    /// conversation picks a model from, under the name the engine lists it
    /// by.
    @MainActor
    func testADownloadFillsItsBarAndTheModelJoinsTheList() {
        let app = launchFreshApp(arguments: ["-ggchat-mock-engine", "no-models"])
        let suggestion = openBrowser(in: app)
        let download = app.buttons["Download, Q4_K_M"].firstMatch
        XCTAssertTrue(tap(suggestion, untilExists: download), "the suggestion did not open its repository")

        let bar = app.progressIndicators["download-bar"].firstMatch
        XCTAssertTrue(tap(download, untilExists: bar), "Download put up no bar")
        // How much has come shows only while the download runs, for eight
        // of its ten seconds, so it is looked for first.
        let soFar = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " of 1.07 GB")).firstMatch
        XCTAssertTrue(soFar.waitForExistence(timeout: 10), "the row does not say how much of the download has come")
        XCTAssertTrue(
            app.buttons["Cancel download, Q4_K_M"].firstMatch.waitForExistence(timeout: 5),
            "the download offers no Cancel")
        attach(app, name: "on-device-download")
        let downloaded = app.descendants(matching: .any)["downloaded"].firstMatch
        XCTAssertTrue(downloaded.waitForExistence(timeout: 30), "the download never finished")
        XCTAssertFalse(bar.exists, "the bar stayed after the download was done")

        // Done is on the browser's first page, the way back from this one,
        // whose title is the last part of the repository's name.
        let back = app.navigationBars["phone-1.7b-GGUF"].buttons.element(boundBy: 0)
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(tap(back, untilExists: done), "going back did not reach the browser's first page")
        XCTAssertTrue(waitUntilHittable(done, timeout: 10), "the browser offers no Done")
        done.tap()
        // The pill names the model too once it is the provider's default,
        // so the witness is a row of the list, which only the open pill shows.
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model, '")).firstMatch
        let joined = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH 'Model, ')", "mock-phone-1.7b-Q4_K_M")
        ).firstMatch
        XCTAssertTrue(tap(pill, untilExists: joined), "the downloaded model did not join the model list")
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
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.phoneModel)).firstMatch
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
