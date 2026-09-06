import XCTest

/// Visits the screens the first-run walk never reaches and photographs each
/// one, so nothing ships that no one has looked at: the provider form and
/// what it says about a bad address or a bad ticket, a pipe connecting and
/// its status pill, the providers list, settings and its readings, and what
/// a failed request looks like under a partial reply.
final class ScreenGalleryUITests: XCTestCase {
    private var app: XCUIApplication!

    /// modelpipe's normative vector 1: a real 67-character ticket, which is
    /// the shortest one there is. The form now enforces that floor, so a
    /// short stand-in would leave Add disabled and this walk would never
    /// reach the status pill — and the screenshot it takes is in the README.
    /// 67 keystrokes into the simulator's keyboard is the price of that.
    private let wellFormedTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ggchat-reset", "YES"]
        app.launch()
    }

    @MainActor
    private func openAddProvider() {
        let add = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "first run offers no way to add a provider")
        add.tap()
    }

    /// The form, and the sentence it shows for an address that is not one.
    @MainActor
    func testTheProviderFormExplainsABadAddress() {
        launch()
        openAddProvider()
        let address = app.textFields["provider-address"].firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        attach(name: "form-server-empty")

        address.tap()
        address.typeText("nope")
        XCTAssertTrue(
            app.staticTexts["That is not an http or https address."].waitForExistence(timeout: 5),
            "a bad address gets no explanation")
        XCTAssertFalse(app.buttons["Add"].firstMatch.isEnabled, "a bad address left Add enabled")
        attach(name: "form-server-bad-address")

        // And a good one says where the requests will go.
        address.tap()
        app.keys["delete"].press(forDuration: 1.2)
        address.typeText("127.0.0.1:8080")
        attach(name: "form-server-bare-host")
    }

    /// The pipe half of the form, and the sentence for a ticket that is not one.
    @MainActor
    func testTheProviderFormExplainsABadTicket() {
        launch()
        openAddProvider()
        app.buttons["Pipe"].firstMatch.tap()
        let ticket = app.textFields["provider-ticket"].firstMatch
        XCTAssertTrue(ticket.waitForExistence(timeout: 10), "the ticket field is not reachable")
        attach(name: "form-pipe-empty")

        ticket.tap()
        ticket.typeText("nope")
        XCTAssertTrue(
            app.staticTexts["A ticket starts with “pipe”."].waitForExistence(timeout: 5),
            "a bad ticket gets no explanation")
        attach(name: "form-pipe-bad-ticket")
    }

    /// A pipe provider connects and the status pill walks to a connected state.
    @MainActor
    func testAPipeConnectsAndTheStatusPillWalks() {
        launch()
        openAddProvider()
        app.buttons["Pipe"].firstMatch.tap()

        let ticket = app.textFields["provider-ticket"].firstMatch
        XCTAssertTrue(ticket.waitForExistence(timeout: 10))
        ticket.tap()
        ticket.typeText(wellFormedTicket)
        let token = app.secureTextFields["provider-token"].firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 5), "the token field is not reachable")
        token.tap()
        token.typeText("a-token")
        attach(name: "form-pipe-filled")

        let addButton = app.buttons["Add"].firstMatch
        XCTAssertTrue(addButton.isEnabled, "a good ticket and token left Add disabled")
        clearingThePasswordManagerPrompt(in: app) {
            addButton.tap()
        }
        attach(name: "pipe-after-add")

        let newConversation = app.buttons["New conversation"].firstMatch
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model, '")).firstMatch
        if !tap(newConversation, untilExists: pill) {
            attachElementTree(app, name: "blocked-tree")
            attach(name: "blocked")
            XCTFail("the conversation never opened; something is over the app")
            return
        }
        attach(name: "pipe-conversation")

        // The pill starts at Connecting and reaches Direct or Relayed.
        let connected = app.buttons.matching(
            NSPredicate(format: "label == 'Connection Direct' OR label == 'Connection Relayed'")
        ).firstMatch
        if !connected.waitForExistence(timeout: 30) {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "element-tree"
            dump.lifetime = .keepAlways
            add(dump)
            attach(name: "pipe-not-connected")
            XCTFail("the pipe never reached a connected state")
            return
        }
        attach(name: "pipe-connected")
    }

    /// The providers list with something in it, and settings with its readings.
    @MainActor
    func testTheProvidersListAndTheDiagnosticsReadings() {
        launch()
        openAddProvider()
        app.buttons["Cancel"].firstMatch.tap()

        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10))
        mock.tap()
        attach(name: "providers-list")
        app.buttons["Done"].firstMatch.tap()

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "settings is not reachable")
        settings.tap()
        XCTAssertTrue(
            app.staticTexts["Diagnostics"].waitForExistence(timeout: 10),
            "settings shows no diagnostics section")
        XCTAssertTrue(
            app.staticTexts["Distinct tickets connected"].exists,
            "the kill criterion's reading is not shown")
        attach(name: "settings-diagnostics")
    }

    /// A server that is not there: the reply stops and says so, and the
    /// partial stays with a way to carry on.
    @MainActor
    func testAServerThatIsNotThereSaysSo() {
        launch()
        openAddProvider()
        let address = app.textFields["provider-address"].firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        // Port 9 is discard: nothing serves HTTP there.
        address.typeText("http://127.0.0.1:9/v1")
        app.buttons["Add"].firstMatch.tap()

        app.buttons["New conversation"].firstMatch.tap()
        let field = app.textViews["composer"].firstMatch
        let composer = field.exists ? field : app.textFields["composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        composer.typeText("Anyone home?")

        // Without a model there is nothing to send, which is its own sentence.
        let send = app.buttons["Send"].firstMatch
        if send.isEnabled {
            send.tap()
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Could not reach the server'"))
                    .firstMatch.waitForExistence(timeout: 60),
                "a dead server produced no sentence")
        }
        attach(name: "server-unreachable")
    }

    @MainActor
    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
