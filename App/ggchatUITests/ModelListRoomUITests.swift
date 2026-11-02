import XCTest

/// The model list opened while the keyboard is up, walked on the DEBUG mock,
/// which lists two models: opening the list puts the keyboard away, and the
/// list is sized from the chat's room, so both of its rows are shown whole
/// above the pill rather than one and half of the next (#277).
final class ModelListRoomUITests: XCTestCase {
    @MainActor
    func testTheListOpenedWhileTypingPutsTheKeyboardAwayAndShowsEveryRow() {
        let app = launchFreshApp()
        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        let pill = openConversation(in: app)

        XCTAssertTrue(caret(in: composer(in: app), of: app), "the composer never took the caret")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'model-row-'"))
        XCTAssertTrue(tap(pill, untilExists: rows.firstMatch, sweeping: false), "the model list never opened")
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 5), "opening the model list left the keyboard up")

        // The list's rows are listed as soon as the mock answers; give the
        // list a moment to settle at the height the room gives it.
        let second = rows.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 15), "the mock's second model is not in the list")
        let heading = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'model-section-'"))
            .firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "the list has no provider heading")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "model-list-after-typing"
        shot.lifetime = .keepAlways
        add(shot)

        // The pill's button stands for the whole glass, list and all, so
        // the line the rows must end above is its symbol's.
        let symbol = app.images["cpu"].firstMatch
        XCTAssertTrue(symbol.exists, "the pill has no symbol")
        let top = symbol.frame.minY
        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            XCTAssertLessThanOrEqual(
                row.frame.maxY, top + 1,
                "\(row.identifier) runs \(row.frame.maxY - top) points into the pill: the list is cut short")
            XCTAssertGreaterThanOrEqual(
                row.frame.minY, heading.frame.maxY - 1, "\(row.identifier) is above the list's heading")
        }
    }
}
