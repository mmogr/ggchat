import XCTest

/// The model list closes on a tap outside it, as a menu does, walked on the
/// DEBUG mock: a tap on the transcript closes it, and so does a tap in the
/// message field, which takes the caret as it would with the list shut.
final class ModelListDismissUITests: XCTestCase {
    @MainActor
    func testATapOutsideTheListClosesIt() {
        let app = launchFreshApp()
        openProviderForm(in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
        let pill = openConversation(in: app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'model-row-'"))

        // Near the top of the window: the transcript, well clear of the
        // list, which opens upward from the pill at the bottom.
        XCTAssertTrue(tap(pill, untilExists: rows.firstMatch, sweeping: false), "the model list never opened")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(rows.firstMatch.waitForNonExistence(timeout: 5), "a tap on the transcript left the list open")

        XCTAssertTrue(tap(pill, untilExists: rows.firstMatch, sweeping: false), "the model list never opened again")
        composer(in: app).tap()
        XCTAssertTrue(
            rows.firstMatch.waitForNonExistence(timeout: 5), "a tap in the message field left the list open")
    }
}
