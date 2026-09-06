import Darwin
import XCTest

/// The screens left over: gglib's status pane, the reconnect a closed pipe
/// offers, and the whole app at an accessibility type size. Each one was
/// written and unit-tested but never looked at.
final class RemainingScreensUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let localServer = (host: "127.0.0.1", port: 8080)

    @MainActor
    private func launch(typeSize: String? = nil) {
        app = launchFreshApp(typeSize: typeSize)
    }

    @MainActor
    private func addMockProvider() {
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30))
        addProvider.tap()
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Providers"].firstMatch.tap()
        let mock = app.buttons["Add mock provider"].firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 10))
        mock.tap()
        app.buttons["Done"].firstMatch.tap()
    }

    /// gglib's "what is the server doing" pane, which is hidden for anything
    /// that does not answer the endpoint.
    @MainActor
    func testTheServerStatusPaneAgainstARealServer() throws {
        try XCTSkipUnless(Self.somethingIsListening(), "start gglib to run this")
        launch()
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30))
        addProvider.tap()
        let address = app.textFields["provider-address"].firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        address.tap()
        address.typeText("http://\(Self.localServer.host):\(Self.localServer.port)/v1")
        app.buttons["Add"].firstMatch.tap()

        app.buttons["New conversation"].firstMatch.tap()
        let statusButton = app.buttons["Server status"].firstMatch
        XCTAssertTrue(
            statusButton.waitForExistence(timeout: 30),
            "gglib answers the status endpoint, so the pane should be offered")
        statusButton.tap()

        XCTAssertTrue(app.staticTexts["Slots"].waitForExistence(timeout: 20), "the pane never filled in")
        XCTAssertTrue(app.staticTexts["Active connections"].exists)
        attach(name: "proxy-status-pane")
        app.buttons["Done"].firstMatch.tap()
    }

    /// The mock provider does not answer the status endpoint, so the button
    /// must not be there at all.
    @MainActor
    func testTheStatusPaneIsHiddenForAServerThatDoesNotReport() {
        launch()
        addMockProvider()
        app.buttons["New conversation"].firstMatch.tap()
        XCTAssertTrue(waitUntilHittable(composer(in: app), timeout: 20), "the composer never appeared")
        XCTAssertFalse(
            app.buttons["Server status"].exists,
            "the status pane is offered for a provider that does not report one")
    }

    /// A closed pipe turns its pill into a way back.
    @MainActor
    func testAClosedPipeOffersAReconnect() {
        launch()
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30))
        addProvider.tap()
        app.buttons["Pipe"].firstMatch.tap()
        let ticket = app.textFields["provider-ticket"].firstMatch
        XCTAssertTrue(ticket.waitForExistence(timeout: 10))
        ticket.tap()
        ticket.typeText("pipeabcdefghijklmnop")
        let token = app.secureTextFields["provider-token"].firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        token.tap()
        token.typeText("a-token")

        clearingThePasswordManagerPrompt(in: app) {
            app.buttons["Add"].firstMatch.tap()
        }

        let newConversation = app.buttons["New conversation"].firstMatch
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model, '")).firstMatch
        XCTAssertTrue(tap(newConversation, untilExists: pill), "the conversation never opened")

        let connected = app.buttons.matching(
            NSPredicate(format: "label == 'Connection Direct' OR label == 'Connection Relayed'")
        ).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 30), "the pipe never connected")

        // Close it from the debug switch, which is what a dropped pipe looks
        // like. Settings lives on the conversation list, so go back for it.
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(
            tap(app.navigationBars.buttons.element(boundBy: 0), untilExists: settings),
            "going back did not reach the conversation list")

        let force = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Force '")).firstMatch
        XCTAssertTrue(tap(settings, untilExists: force), "DEBUG builds can force a pipe closed")
        force.tap()
        app.buttons["Done"].firstMatch.tap()

        // Back into the conversation to see what its pill now says.
        let reconnect = app.buttons["Connection Reconnect"].firstMatch
        XCTAssertTrue(
            tap(app.cells.firstMatch, untilExists: reconnect),
            "a closed pipe offers no way back")
        attach(name: "pipe-closed")
        XCTAssertTrue(reconnect.isEnabled, "the reconnect pill is not tappable")
        XCTAssertTrue(tap(reconnect, untilExists: connected), "reconnect did not bring the pipe back")
        attach(name: "pipe-reconnected")
    }

    /// The whole walk at the largest accessibility type size. The launch
    /// argument is accepted silently when misspelled, so the test measures a
    /// row at both sizes and fails if nothing actually grew.
    @MainActor
    func testTheAppAtAnAccessibilityTypeSize() {
        let normal = heightOfTheAssistantLabel(typeSize: nil, screenshot: nil)
        let large = heightOfTheAssistantLabel(
            typeSize: Self.accessibilityXXXL, screenshot: "ax5-reply")
        XCTAssertGreaterThan(
            large, normal * 1.3,
            "text did not grow at the largest accessibility size: \(normal)pt to \(large)pt")
    }

    /// Walks to a finished reply and returns the height of a row that scales
    /// with the type size.
    @MainActor
    private func heightOfTheAssistantLabel(typeSize: String?, screenshot: String?) -> CGFloat {
        app = launchFreshApp(typeSize: typeSize)
        addMockProvider()
        app.buttons["New conversation"].firstMatch.tap()
        XCTAssertTrue(waitUntilHittable(composer(in: app), timeout: 20), "the composer is unreachable")
        composer(in: app).tap()
        composer(in: app).typeText("Hello")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isHittable, "the send button is not tappable at this type size")
        send.tap()

        let assistant = app.staticTexts["ASSISTANT"].firstMatch
        XCTAssertTrue(assistant.waitForExistence(timeout: 60), "no reply arrived")
        wait(
            for: [expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.buttons["Send"])],
            timeout: 120)
        if let screenshot { attach(name: screenshot) }
        return assistant.frame.height
    }

    /// Whether a server is listening where gglib usually is. A plain TCP
    /// connect, so the probe is not subject to transport security rules.
    private static func somethingIsListening() -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(localServer.port).bigEndian)
        address.sin_addr.s_addr = inet_addr(localServer.host)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }

    @MainActor
    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
