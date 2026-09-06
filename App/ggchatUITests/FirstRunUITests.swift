import Darwin
import XCTest

/// Drives the real app the way a first-time user does: add a provider, start
/// a conversation, send a message, watch the reply stream in.
///
/// The mock run is hermetic and always runs. The live run does the same thing
/// against a server on the host's loopback and skips when nothing answers, so
/// CI is unaffected and a developer with gglib running gets the real thing.
final class FirstRunUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Where gglib listens by default. The simulator shares the host's
    /// loopback, so this is the same server the Mac is running.
    private static let localServer = (host: "127.0.0.1", port: 8080)
    private static var localServerBaseURL: String {
        "http://\(localServer.host):\(localServer.port)/v1"
    }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ggchat-reset", "YES"]
        app.launch()
    }

    /// The claim from the handoff: a first-time user is streaming in under a
    /// minute, touching nothing but the buttons in front of them.
    func testFirstRunWithTheMockProvider() throws {
        try runFirstRun(liveURL: nil)
    }

    /// The same walk, against a real OpenAI-compatible server.
    func testFirstRunAgainstAServerOnThisMachine() throws {
        try XCTSkipUnless(
            Self.somethingIsListening(),
            "nothing is listening on \(Self.localServerBaseURL); start gglib to run this")
        try runFirstRun(liveURL: Self.localServerBaseURL)
    }

    private func runFirstRun(liveURL: String?) throws {
        XCTContext.runActivity(named: "provider: \(liveURL ?? "the DEBUG mock")") { _ in }
        let suffix = liveURL == nil ? "mock" : "live"

        // 1. The first screen offers a way in.
        let addProvider = app.buttons["Add a provider"].firstMatch
        XCTAssertTrue(addProvider.waitForExistence(timeout: 30), "first run offers no way to add a provider")
        addProvider.tap()
        attach(name: "01-add-provider-\(suffix)")

        // 2. Add the provider.
        if let liveURL {
            let address = app.textFields["provider-address"].firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 10), "the address field is not reachable")
            address.tap()
            address.typeText(liveURL)
            let add = app.buttons["Add"].firstMatch
            XCTAssertTrue(add.isEnabled, "a valid address left the Add button disabled")
            add.tap()
        } else {
            // The mock lives on the providers list, one hop away.
            app.buttons["Cancel"].firstMatch.tap()
            app.buttons["Providers"].firstMatch.tap()
            let mock = app.buttons["Add mock provider"].firstMatch
            XCTAssertTrue(mock.waitForExistence(timeout: 10), "DEBUG builds offer a mock provider")
            mock.tap()
            app.buttons["Done"].firstMatch.tap()
        }

        // 3. Start a conversation.
        let newConversation = app.buttons["New conversation"].firstMatch
        XCTAssertTrue(newConversation.waitForExistence(timeout: 10), "no way to start a conversation")
        newConversation.tap()

        // 4. The pill names the model that was actually listed, so a live run
        // cannot pass by quietly falling back to the mock.
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Model, '")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the model pill never appeared")
        if liveURL == nil {
            XCTAssertEqual(pill.label, "Model, mock-27b")
        } else {
            XCTAssertNotEqual(pill.label, "Model, mock-27b", "a live run fell back to the mock provider")
            XCTAssertNotEqual(pill.label, "Model, Choose a model", "the live server listed no models")
        }
        attach(name: "02-empty-conversation-\(suffix)")

        // 5. Send a message.
        let composer = app.textViews["composer"].firstMatch
        let field = composer.exists ? composer : app.textFields["composer"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "the composer never appeared")
        field.tap()
        field.typeText("Say hello in three words.")
        let send = app.buttons["Send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled, "the send button stays disabled with a message typed")
        send.tap()

        // 6. The question lands in the transcript and a reply streams in.
        XCTAssertTrue(
            app.staticTexts["Say hello in three words."].waitForExistence(timeout: 10),
            "the question never appeared in the transcript")
        XCTAssertTrue(
            app.staticTexts["ASSISTANT"].firstMatch.waitForExistence(timeout: 120), "no reply arrived")
        attach(name: "03-streaming-\(suffix)")

        // 7. It finishes: the stop button turns back into send.
        wait(
            for: [expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.buttons["Send"])],
            timeout: 180)
        attach(name: "04-reply-complete-\(suffix)")
    }

    /// A plain TCP connect, so the probe is not subject to the test runner's
    /// transport security rules.
    private static func somethingIsListening() -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(localServer.port).bigEndian)
        address.sin_addr.s_addr = inet_addr(localServer.host)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }

    private func attach(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
