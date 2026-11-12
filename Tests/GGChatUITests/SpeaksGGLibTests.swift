import GGChatCore
import XCTest

@testable import GGChatUI

/// What of gglib each kind of provider speaks: whether it is sent gglib's
/// own keys, whether a reply to it is a run, and whether its conversations
/// have a Draw switch. A paired Mac is gglib by its kind; a server by
/// address is only once its model list has said so. One case per
/// question per kind, so a kind that is added answers each one here.
@MainActor
final class SpeaksGGLibTests: XCTestCase {
    private let pipe = ProviderConfig(
        name: "home",
        kind: .pipe(ticketDigest: Ticket.digest("pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na")))
    private let address = ProviderConfig(
        name: "gglib on the Mac", kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:8080/v1")!))
    private let thisIPhone = ProviderConfig(name: "This iPhone", kind: .onDevice)

    private func makeModel() -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "SpeaksGGLibTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    private let current = GGLibAnswer.server(.serving("0.35.0"))

    /// A paired Mac is gglib by its kind, whatever its list said, and before
    /// it has been read at all.
    func testAPairedMacSpeaksGGLib() {
        let model = makeModel()
        XCTAssertTrue(model.speaksGGLib(pipe))
        model.gglibAnswers[pipe.id] = .silent
        XCTAssertTrue(model.speaksGGLib(pipe))
    }

    /// A server by address is gglib once its list has said so, and not
    /// before or when it said nothing.
    func testAnAddressSpeaksGGLibOnlyOnceItsListSaidSo() {
        let model = makeModel()
        XCTAssertFalse(model.speaksGGLib(address), "a server not listed yet was taken to be gglib")
        model.gglibAnswers[address.id] = .silent
        XCTAssertFalse(model.speaksGGLib(address))
        model.gglibAnswers[address.id] = current
        XCTAssertTrue(model.speaksGGLib(address))
    }

    /// A reply to a paired Mac or a server by address is a run only once its
    /// gglib has said it serves runs: not before its list is read, not when
    /// the list says nothing, and not when it lists other features alone.
    func testAReplyIsARunOnlyWhereTheGGLibSaysItServesRuns() {
        let model = makeModel()
        for config in [pipe, address] {
            XCTAssertFalse(model.hasRuns(config), "\(config.name) not listed yet")
            model.gglibAnswers[config.id] = .silent
            XCTAssertFalse(model.hasRuns(config), "\(config.name) said nothing")
            model.gglibAnswers[config.id] = .server(.serving("0.35.0", [.chats, .drawing, .status]))
            XCTAssertFalse(model.hasRuns(config), "\(config.name) does not serve runs")
            model.gglibAnswers[config.id] = current
            XCTAssertTrue(model.hasRuns(config), "\(config.name) serves runs")
        }
    }

    func testAPairedMacCanDraw() {
        XCTAssertTrue(makeModel().canDraw(pipe))
    }

    /// A server by address has the switch once its list said it is gglib,
    /// where it says drawing needs a paired Mac.
    func testAnAddressHasTheDrawSwitchOnlyOnceItsListSaidItIsGGLib() {
        let model = makeModel()
        XCTAssertFalse(model.canDraw(address))
        model.gglibAnswers[address.id] = current
        XCTAssertTrue(model.canDraw(address))
    }

    /// This device's engine is gglib by its kind.
    func testThisIPhonesEngineSpeaksGGLib() {
        let model = makeModel()
        XCTAssertTrue(model.speaksGGLib(thisIPhone))
        model.gglibAnswers[thisIPhone.id] = .silent
        XCTAssertTrue(model.speaksGGLib(thisIPhone))
    }

    /// It streams its replies, has no status pane and draws nothing,
    /// whatever its list said.
    func testThisIPhonesEngineHasNoRunsPaneOrDrawSwitch() throws {
        let model = makeModel()
        model.gglibAnswers[thisIPhone.id] = current
        XCTAssertFalse(model.hasRuns(thisIPhone))
        XCTAssertFalse(model.canDraw(thisIPhone))
        XCTAssertFalse(model.serves(.status, thisIPhone))
    }
}
