import GGChatCore
import XCTest

@testable import GGChatUI

/// What happens to the pipe a one-time code was spent over when the write that
/// should have kept it fails.
///
/// The pairing itself succeeded on the wire in every test here: the far machine
/// minted a key and handed back a live pipe. What fails is this side's own
/// bookkeeping, which is the only window in which a pipe can be left with
/// nothing in the app holding it.
final class AppModelPairingFailureTests: XCTestCase {
    /// modelpipe's normative vector 1, and a code, so the string is one the
    /// reader accepts.
    private let pairing = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na-483920"
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// A connector whose paired sessions count their own hang-ups, with the
    /// holding released at once: here the count is the whole point, not the
    /// window.
    @MainActor
    private func connector() -> HeldShutdownConnector {
        let connector = HeldShutdownConnector(registry: LoopbackProviderRegistry())
        connector.release()
        return connector
    }

    /// The key would not save, so there is no provider to keep a pipe for —
    /// and the pipe goes. Dropping it would close nothing: no type here has a
    /// `deinit`, and the session's driver holds the binding's pipe open, so the
    /// far machine would count this device as connected until the app was
    /// quit, with nothing in `pipeSessions` for the background pass to find.
    @MainActor
    func testAPairingWhoseKeyWillNotSaveHangsUpThePipeItWasRedeemedOver() async throws {
        let connector = connector()
        let model = AppModel(
            store: InMemoryStore(), secrets: FailingSecrets(failOn: .token), log: NoopLogSink(),
            pipeConnector: connector)
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: "abc"))

        do {
            try await model.addPairedProvider(
                config, pairing: pairing, ticket: ticket, deviceName: nil)
            XCTFail("a key that would not save produced a paired provider")
        } catch {
            XCTAssertEqual((error as? KeychainError)?.kind, .token)
        }

        XCTAssertEqual(
            connector.shutdownsStarted, 1,
            "the pipe the code was spent over was left up with nothing holding it")
        XCTAssertTrue(model.providers.isEmpty, "a provider was added despite its key failing to save")
        XCTAssertNil(model.pipeStatus(for: config.id), "a provider nobody added was given a pill")
    }

    /// The same on the edit path, where the write fails because the provider
    /// itself went away while the pairing was out — the case
    /// ``AppModel/updateProvider(_:credentials:)``'s own doc names.
    @MainActor
    func testARePairingOfAProviderThatWentAwayHangsUpTheNewPipe() async throws {
        let connector = connector()
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            pipeConnector: connector)
        // Never added, which is what `updateProvider` sees after a removal.
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: "abc"))

        do {
            try await model.updatePairedProvider(
                config, pairing: pairing, ticket: ticket, deviceName: nil)
            XCTFail("a provider that is not there was re-paired")
        } catch {
            XCTAssertTrue(error is ProviderEditError, "\(error)")
        }

        XCTAssertEqual(
            connector.shutdownsStarted, 1,
            "the pipe the new code was spent over was left up with nothing holding it")
    }

    /// And a pairing that lands cleanly still keeps its pipe: the guard above
    /// must not hang up a pipe the app is about to install, which is the whole
    /// reason `mpPair` hands one back.
    @MainActor
    func testAPairingThatStoresCleanlyKeepsItsPipe() async throws {
        let connector = connector()
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            pipeConnector: connector)
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: "abc"))

        try await model.addPairedProvider(config, pairing: pairing, ticket: ticket, deviceName: nil)

        XCTAssertEqual(connector.shutdownsStarted, 0, "the pipe it paired over was hung up anyway")
        XCTAssertEqual(model.providers.count, 1)
        XCTAssertNotNil(model.pipeStatus(for: config.id), "the paired pipe was not installed")
    }
}
