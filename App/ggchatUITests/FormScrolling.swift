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

    /// Scrolls whatever is on screen by one swipe. The swipe is
    /// `XCUIApplication.swipeUp()`'s, from the app's centre, unless that
    /// centre is on a text field or the keyboard: a swipe on a field moves
    /// the caret into it and scrolls nothing, and a swipe on the keyboard
    /// scrolls nothing at all. Then it starts on the lowest label above the
    /// keyboard instead, which is on the form and not on a field. An iPhone
    /// Duo's outer display is 678 points tall, and the provider form's
    /// ticket field sits across its centre once the keyboard is up, as it
    /// does on an iPhone 17 Pro; on an iPad the centre is clear and this is
    /// the swipe it always was.
    ///
    /// "Above the keyboard" is above ``keyboardTop(in:)``, not above the
    /// keyboard element, which leaves out the bar of suggestions over the
    /// keys. A label reaching into that bar was swiped there: the swipe
    /// pressed the bar's Passwords button instead of scrolling the form, and
    /// the walk then either never scrolled or lost its next tap.
    @MainActor
    func nudge(in app: XCUIApplication, up: Bool = true) {
        let window = app.windows.firstMatch.frame
        let centre = CGPoint(x: window.midX, y: window.midY)
        let fields =
            app.textFields.allElementsBoundByIndex + app.secureTextFields.allElementsBoundByIndex
            + app.textViews.allElementsBoundByIndex
        let ceiling = keyboardTop(in: app) ?? window.maxY
        let covered = centre.y >= ceiling || fields.contains { $0.frame.contains(centre) }
        var handle: XCUIElement?
        if covered {
            let labels = app.staticTexts.allElementsBoundByIndex.filter { label in
                label.isHittable && label.frame.maxY < ceiling && !fields.contains { $0.frame.intersects(label.frame) }
            }
            handle = labels.max(by: { $0.frame.maxY < $1.frame.maxY })
        }
        switch (handle, up) {
        case (let handle?, true): handle.swipeUp()
        case (let handle?, false): handle.swipeDown()
        case (nil, true): app.swipeUp()
        case (nil, false): app.swipeDown()
        }
    }

    /// Where the keyboard's part of the screen starts, or nil with no
    /// keyboard up. The keyboard element is the keys alone; the bar of
    /// suggestions over them, with its Passwords button, is a sibling of it in
    /// the same container, so the top is that of a container around the keys
    /// that starts at most 100 points above them: on an iPhone 17 Pro, 539
    /// points where the keys start at 583. A larger container that also holds
    /// the keyboard, such as a chat screen's, is not the keyboard's part.
    @MainActor
    func keyboardTop(in app: XCUIApplication) -> CGFloat? {
        let keyboard = app.keyboards.element
        guard keyboard.exists else { return nil }
        let keys = keyboard.frame
        let containers = app.otherElements.containing(.keyboard, identifier: nil).allElementsBoundByIndex
        let tops = containers.map(\.frame)
            .filter { $0.minY < keys.minY && $0.minY >= keys.minY - 100 && $0.maxY >= keys.maxY - 1 }
            .map(\.minY)
        return tops.min() ?? keys.minY
    }
}
