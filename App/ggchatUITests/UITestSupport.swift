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
    /// over it, and a tap then goes to that instead.
    @MainActor
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable { return true }
            _ = element.waitForExistence(timeout: 0.5)
        }
        return false
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
    /// monitor catches it on the next interaction; the poll catches it when
    /// it arrives late. Both are needed.
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

        let springboard: XCUIApplication? = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            for source in [springboard, app] {
                guard let notNow = source?.buttons["Not Now"], notNow.exists, notNow.isHittable else { continue }
                notNow.tap()
                return
            }
            _ = springboard?.alerts.firstMatch.waitForExistence(timeout: 0.5)
        }
    }
}
