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
    @MainActor
    func composer(in app: XCUIApplication) -> XCUIElement {
        let textView = app.textViews["composer"].firstMatch
        return textView.exists ? textView : app.textFields["composer"].firstMatch
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
}
