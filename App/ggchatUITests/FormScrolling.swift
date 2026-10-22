import XCTest

/// Scrolling a form on a screen the keyboard covers half of.
extension XCTestCase {
    /// Scrolls a screen until an element is there to be tapped. SwiftUI
    /// leaves the rows of a long `Form` below the fold out of the tree, so
    /// such a control reports `exists == false`, which reads as one never
    /// built. Swipes, as `scrollToElement` needs a frame it has not got.
    @MainActor
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0...swipes {
            if element.exists, element.isHittable { return true }
            nudge(in: app)
        }
        return element.exists && element.isHittable
    }

    /// Scrolls whatever is on screen up by one swipe, which starts on a
    /// label of the form rather than at the app's centre: with the keyboard
    /// up, the centre of a short screen is the keyboard, and a swipe there
    /// scrolls nothing. An iPhone Duo's outer display is 678 points tall,
    /// and the provider form's token field sits under the keyboard its
    /// ticket field raised; a swipe on the "Pairing string" header scrolls
    /// the form the hundred points that bring the token into view. Not on a
    /// field: a swipe there moves the caret into it instead, and the walk
    /// then types into the wrong one. The lowest label above the keyboard
    /// is taken, so the swipe has the most room to travel.
    @MainActor
    func nudge(in app: XCUIApplication, up: Bool = true) {
        let keyboard = app.keyboards.element
        let ceiling = keyboard.exists ? keyboard.frame.minY : app.windows.firstMatch.frame.maxY
        let labels = app.staticTexts.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.maxY < ceiling }
        let handle = labels.max(by: { $0.frame.maxY < $1.frame.maxY })
        switch (handle, up) {
        case (let handle?, true): handle.swipeUp()
        case (let handle?, false): handle.swipeDown()
        case (nil, true): app.swipeUp()
        case (nil, false): app.swipeDown()
        }
    }
}
