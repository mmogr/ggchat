import GGChatCore
import Security
import XCTest

@testable import GGChatUI

/// A Keychain that refuses to read a pipe's ticket or token, as one does
/// before the device's first unlock, is said as that refusal and not as a
/// credential gone missing (#85). One that really is missing still says so:
/// `AppModelPipeTests.testConnectWithoutSecretsRefusesWithASentence`.
final class AppModelKeychainReadTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(
        _ secrets: FailingSecrets, log: any LogSink = NoopLogSink()
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelKeychainReadTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: secrets, log: log, registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    /// What the person is told when the Keychain will not read `kind`.
    private func refusal(_ kind: SecretKind) -> String {
        let error = KeychainError(status: errSecInteractionNotAllowed, kind: kind, reading: true)
        return "home was not dialled. \(error.localizedDescription)"
    }

    /// The ticket and the token alike: the alert carries the Keychain's own
    /// reason, and no dial goes out.
    @MainActor
    func testAReadTheKeychainRefusesIsSaidAsThatRefusal() async throws {
        for kind in [SecretKind.ticket, .token] {
            let secrets = FailingSecrets(failOn: .apiKey)
            let (model, config) = try makeModel(secrets)
            secrets.refusesToRead = kind

            await model.connectPipe(for: config)

            let sentence = try XCTUnwrap(model.lastError, "a refused read of the \(kind.name) said nothing")
            XCTAssertEqual(sentence, refusal(kind))
            XCTAssertFalse(sentence.contains("missing"), "a refused read was called missing: \(sentence)")
            XCTAssertNil(model.pipeStatus(for: config.id), "a dial went out with nothing to dial with")
        }
    }

    /// A send waiting on the pipe takes the refusal onto its question, as it
    /// takes a refused dial's, and no alert is raised as well.
    @MainActor
    func testASendWaitingOnThePipeShowsTheRefusalOnItsQuestion() async throws {
        let secrets = FailingSecrets(failOn: .apiKey)
        let (model, _) = try makeModel(secrets)
        model.newConversation()
        secrets.refusesToRead = .ticket

        let send = try XCTUnwrap(model.send("anyone?"))
        await send.value

        let question = try XCTUnwrap(model.selectedConversation?.messages.first)
        XCTAssertEqual(question.failure?.message, refusal(.ticket))
        XCTAssertNil(model.lastError, "the refusal was raised as an alert as well")
    }

    /// A quiet dial, the kind a return to the foreground makes, raises no
    /// alert, and its log line gives the Keychain's reason.
    @MainActor
    func testAQuietDialLogsTheRefusalAndRaisesNoAlert() async throws {
        let secrets = FailingSecrets(failOn: .apiKey)
        let log = CapturingLogSink()
        let (model, config) = try makeModel(secrets, log: log)
        secrets.refusesToRead = .token

        await model.connectPipe(for: config, quietly: true)

        XCTAssertNil(model.lastError, "a quiet dial raised an alert")
        let reason = KeychainError(status: errSecInteractionNotAllowed, kind: .token, reading: true)
        XCTAssertTrue(
            log.lines.contains("[info] home was not dialled: \(reason.localizedDescription)"),
            "the log does not say why: \(log.lines)")
    }
}
