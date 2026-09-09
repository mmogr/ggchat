import XCTest

/// What every walk through this app needs: a way to wait until a tap will
/// actually land, a way to find the composer whichever kind of element
/// SwiftUI made it, and a way to get iOS's own prompts out of the way.
extension XCTestCase {
    /// A fresh app with nothing saved, so the walk starts at first run.
    /// The raw value of `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`.
    /// Spelling it any other way is accepted silently and changes nothing.
    static var accessibilityXXXL: String { "UICTContentSizeCategoryAccessibilityXXXL" }

    @MainActor
    func launchFreshApp(typeSize: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ggchat-reset", "YES"]
        if let typeSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", typeSize]
        }
        app.launch()
        return app
    }

    /// An element can exist while something the system put on screen sits
    /// over it, and a tap then goes to that instead. On a device that has
    /// not seen this app before, iOS offers to save the token to the
    /// password manager, and that offer can arrive seconds after the sheet
    /// closes, so the wait dismisses whatever is on top as it goes rather
    /// than clearing once up front and hoping.
    @MainActor
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            dismissAnythingOnTop()
            _ = element.waitForExistence(timeout: 0.5)
        }
        return false
    }

    /// Taps the dismissive button of any system prompt currently up. Cheap
    /// enough to call in a loop, and silent when there is nothing there.
    @MainActor
    func dismissAnythingOnTop() {
        // The password manager's offer is drawn by a remote view inside the
        // app under test, not by SpringBoard, so both are swept.
        let sources = [XCUIApplication(), XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        for source in sources {
            for title in ["Not Now", "Cancel", "Dismiss", "Close"] {
                let button = source.buttons[title]
                if button.exists, button.isHittable {
                    button.tap()
                    return
                }
            }
        }
    }

    /// Scrolls a scrollable screen until an element is there to be tapped.
    ///
    /// Not the same problem as `waitUntilHittable`, which waits for something
    /// on top to go away. This one is for something that has never been on
    /// screen at all: SwiftUI does not put every row of a long `Form` into
    /// the accessibility tree at once, so a control below the fold can report
    /// `exists == false` — indistinguishable, from a test, from a control
    /// that was never built. Settings crossed that line when it gained a
    /// section of readings, and the failure read as "the DEBUG build has no
    /// Force button" rather than "scroll down".
    ///
    /// Swipes rather than using `scrollToElement`, which needs a frame the
    /// element does not have while it is outside the tree.
    @MainActor
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0...swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Taps, then checks the tap actually did something, and tries again if
    /// it did not. The password manager's offer can arrive a second time,
    /// after the first has been dismissed, and swallow the tap that follows.
    @MainActor
    @discardableResult
    func tap(_ element: XCUIElement, untilExists witness: XCUIElement, attempts: Int = 4) -> Bool {
        for _ in 0..<attempts where waitUntilHittable(element, timeout: 15) {
            element.tap()
            if witness.waitForExistence(timeout: 8) { return true }
            dismissAnythingOnTop()
        }
        return witness.exists
    }

    /// Puts the caret in a field and waits for the keyboard, because
    /// `XCUIElement.tap()` does not always land where the element is: on an
    /// iPad this app's composer stays unfocused through repeated taps, and
    /// `typeText` then fails with "Neither element nor any descendant has
    /// keyboard focus" while the same point tapped as a coordinate focuses
    /// it. So the tap is placed at the centre of the element's own frame.
    /// The keyboard is the witness: a tap that misses raises none, and
    /// without waiting for one the caller types into nothing.
    @MainActor
    func caret(in element: XCUIElement, of app: XCUIApplication, attempts: Int = 3) -> Bool {
        for _ in 0..<attempts where waitUntilHittable(element, timeout: 15) {
            let middle = element.frame
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: middle.midX, dy: middle.midY))
                .tap()
            if app.keyboards.element.waitForExistence(timeout: 5) { return true }
            dismissAnythingOnTop()
        }
        return false
    }

    /// Everything on screen, for when a wait times out and the screenshot
    /// alone does not say why.
    @MainActor
    func attachElementTree(_ app: XCUIApplication, name: String) {
        let dump = XCTAttachment(string: app.debugDescription)
        dump.name = name
        dump.lifetime = .keepAlways
        add(dump)
    }

    /// SwiftUI exposes a vertical `TextField` as a text view or a text field
    /// depending on how many lines it is showing, so both are asked for.
    ///
    /// The choice is made when this is called, not when the returned element
    /// is used, so it must not be called before the conversation is on
    /// screen: with no composer of either kind present, `textView.exists` is
    /// false and this pins the text-field query, which then never matches
    /// the text view SwiftUI went on to make. Open the conversation with
    /// ``openConversation(in:)`` first and the question is being asked of a
    /// screen that can answer it.
    @MainActor
    func composer(in app: XCUIApplication) -> XCUIElement {
        let textView = app.textViews["composer"].firstMatch
        return textView.exists ? textView : app.textFields["composer"].firstMatch
    }

    /// Opens a conversation and does not return until one is open.
    ///
    /// Every walk starts here, so every walk confirms the tap in the same
    /// way rather than each remembering to. The witness is the model pill,
    /// which is the first thing the conversation screen puts up and is
    /// present whatever the provider did: its label is
    /// `"Model, " + (the model ?? "Choose a model")`, so a server that
    /// listed nothing — or is not there at all — still raises it. That is
    /// what lets one witness serve all of these walks instead of each
    /// needing its own.
    ///
    /// Returns the pill, for the walks that go on to read the model's name
    /// off it.
    @MainActor
    @discardableResult
    func openConversation(in app: XCUIApplication) -> XCUIElement {
        let newConversation = app.buttons["New conversation"].firstMatch
        XCTAssertTrue(newConversation.waitForExistence(timeout: 10), "no way to start a conversation")
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model, '")).firstMatch
        XCTAssertTrue(tap(newConversation, untilExists: pill), "the conversation never opened")
        return pill
    }

    /// iOS offers to save a secure field's contents to the password manager
    /// once the sheet closes, and that alert swallows the next tap. The
    /// monitor catches it on the next interaction; `waitUntilHittable`
    /// catches it when it arrives late. Both are needed.
    @MainActor
    func clearingThePasswordManagerPrompt(in app: XCUIApplication, during work: () -> Void) {
        let monitor = addUIInterruptionMonitor(withDescription: "password manager") { alert in
            for title in ["Not Now", "Cancel", "Dismiss"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        work()
        app.tap()
        dismissAnythingOnTop()
    }

    /// Types the live server's key into the provider form.
    ///
    /// `provider-key` is the Server kind's field, bound to the credential
    /// stored as `.apiKey`. It is not `provider-token`: that is the Pipe
    /// kind's, it holds a different credential, and the form only ever shows
    /// one of the two, so a server walk that reached for it would find
    /// nothing there.
    ///
    /// An empty key types nothing, which leaves a keyless walk exactly as it
    /// was -- including not waking the password manager, whose offer arrives
    /// only once something has been put in a `SecureField`.
    @MainActor
    func typeAPIKey(_ key: String, in app: XCUIApplication) {
        guard !key.isEmpty else { return }
        let field = app.secureTextFields["provider-key"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the API key field is not reachable")
        field.tap()
        field.typeText(key)
    }

    /// Submits the provider form: taps Add, then waits for the sheet to go.
    ///
    /// Nothing may sweep the screen while that sheet is up. Its own
    /// dismissive button is titled "Cancel", which is one of the titles
    /// `dismissAnythingOnTop()` reaches for, so a sweep aimed at the password
    /// manager's offer closes the sheet instead and the provider is never
    /// added -- and the walk then fails a long way further on, looking for
    /// all the world like the server never answered. The offer is handled
    /// afterwards instead, by the retrying `tap(_:untilExists:)` that opens
    /// the conversation, which runs once the sheet is definitely gone.
    @MainActor
    func submitProviderForm(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        app.buttons["Add"].firstMatch.tap()
        XCTAssertTrue(
            cancel.waitForNonExistence(timeout: 20),
            "the provider sheet did not close after Add, so nothing was added")
    }
}
