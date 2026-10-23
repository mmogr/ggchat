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
    /// ticket field sits across its centre once the keyboard is up; on a
    /// taller phone, and on an iPad, the centre is clear and this is the
    /// swipe it always was.
    @MainActor
    func nudge(in app: XCUIApplication, up: Bool = true) {
        let window = app.windows.firstMatch.frame
        let centre = CGPoint(x: window.midX, y: window.midY)
        let fields =
            app.textFields.allElementsBoundByIndex + app.secureTextFields.allElementsBoundByIndex
            + app.textViews.allElementsBoundByIndex
        let keyboard = app.keyboards.element
        let covered =
            (keyboard.exists && keyboard.frame.contains(centre)) || fields.contains { $0.frame.contains(centre) }
        var handle: XCUIElement?
        if covered {
            let ceiling = keyboard.exists ? keyboard.frame.minY : window.maxY
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
}
