import GGChatCore
import XCTest

@testable import GGChatUI

/// What of gglib each kind of provider speaks: whether it is sent gglib's
/// own keys, whether a reply to it is a run, and whether its conversations
/// have a Draw switch. A paired Mac is gglib by its kind; a server by
/// address is only once it has answered the status probe. One case per
/// question per kind, so a kind that is added answers each one here.
@MainActor
final class SpeaksGGLibTests: XCTestCase {
    private let pipe = ProviderConfig(
        name: "home",
        kind: .pipe(ticketDigest: Ticket.digest("pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na")))
    private let address = ProviderConfig(
        name: "gglib on the Mac", kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:8080/v1")!))

    private func makeModel() -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "SpeaksGGLibTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// A paired Mac is gglib whatever the probe said of it, and before it
    /// has been asked at all.
    func testAPairedMacSpeaksGGLib() {
        let model = makeModel()
        XCTAssertTrue(model.speaksGGLib(pipe))
        model.proxyStatusAvailability[pipe.id] = false
        XCTAssertTrue(model.speaksGGLib(pipe))
    }

    /// A server by address is gglib once it has answered the probe, and not
    /// before or when it answered as another server.
    func testAnAddressSpeaksGGLibOnlyOnceItAnsweredTheProbe() {
        let model = makeModel()
        XCTAssertFalse(model.speaksGGLib(address), "a server not asked yet was taken to be gglib")
        model.proxyStatusAvailability[address.id] = false
        XCTAssertFalse(model.speaksGGLib(address))
        model.proxyStatusAvailability[address.id] = true
        XCTAssertTrue(model.speaksGGLib(address))
    }

    /// A reply to a paired Mac is a run, until it answers as one without.
    func testAPairedMacHasRunsUntilItSaysItHasNone() {
        let model = makeModel()
        XCTAssertTrue(model.hasRuns(pipe))
        model.providersWithoutRuns.insert(pipe.id)
        XCTAssertFalse(model.hasRuns(pipe))
    }

    /// A reply to a server by address is a run only once it has answered as
    /// gglib, and until it answers as one without runs.
    func testAnAddressHasRunsOnlyAsGGLibAndUntilItSaysItHasNone() {
        let model = makeModel()
        XCTAssertFalse(model.hasRuns(address))
        model.proxyStatusAvailability[address.id] = true
        XCTAssertTrue(model.hasRuns(address))
        model.providersWithoutRuns.insert(address.id)
        XCTAssertFalse(model.hasRuns(address))
    }

    func testAPairedMacCanDraw() {
        XCTAssertTrue(makeModel().canDraw(pipe))
    }

    /// A server by address has the switch once it has answered as gglib,
    /// where it says drawing needs a paired Mac.
    func testAnAddressHasTheDrawSwitchOnlyOnceItAnsweredTheProbe() {
        let model = makeModel()
        XCTAssertFalse(model.canDraw(address))
        model.proxyStatusAvailability[address.id] = true
        XCTAssertTrue(model.canDraw(address))
    }
}
