import GGChatCore
import XCTest

@testable import GGChatUI

/// A redeemer with a fixed answer, so the app model's pairing path can be
/// walked without a machine on the other end of anything.
private struct FixedRedeemer: PairingRedeemer {
    let outcome: Result<String, PairingError>

    func redeem(code: String, through baseURL: URL) async throws -> String {
        try outcome.get()
    }
}

final class AppModelPairingTests: XCTestCase {
    /// modelpipe's normative vector 1 from `docs/ticket-format-v0.md`.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(_ outcome: Result<String, PairingError>) -> (AppModel, InMemorySecrets) {
        let registry = LoopbackProviderRegistry()
        let secrets = InMemorySecrets()
        let defaults = UserDefaults(suiteName: "AppModelPairingTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            redeemer: FixedRedeemer(outcome: outcome), diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        return (model, secrets)
    }

    private func pipeConfig() -> ProviderConfig {
        ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
    }

    /// The whole point of the branch: the key is fetched over the pipe, not
    /// read off the other machine's screen and typed in here.
    @MainActor
    func testARedeemedCodeBecomesTheProvidersTokenAndThePipeConnects() async throws {
        let (model, secrets) = makeModel(.success("far-machine-key"))
        let config = pipeConfig()

        try await model.addPairedProvider(config, ticket: ticket, code: "483920")

        XCTAssertEqual(model.providers.map(\.id), [config.id])
        XCTAssertEqual(
            try secrets.secret(.token, for: config.id), "far-machine-key",
            "the key the code was traded for is the token; nothing was carried by hand")
        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), ticket)
        XCTAssertNotNil(model.pipeSession(for: config.id), "pairing ends with the pipe up")
        XCTAssertEqual(model.diagnostics.ticketDigests, [Ticket.digest(ticket)])
    }

    /// A code is spent whether or not it worked, so a refusal must leave
    /// nothing half-added for the next attempt to trip over.
    @MainActor
    func testARefusedCodeAddsNoProviderAndSaysWhy() async throws {
        let (model, secrets) = makeModel(.failure(.refused))
        let config = pipeConfig()

        do {
            try await model.addPairedProvider(config, ticket: ticket, code: "000000")
            XCTFail("a refused code added a provider")
        } catch let error as PairingError {
            XCTAssertEqual(error, .refused)
            XCTAssertTrue(error.localizedDescription.contains("gglib remote enable"), error.localizedDescription)
        }

        XCTAssertTrue(model.providers.isEmpty)
        XCTAssertNil(try secrets.secret(.ticket, for: config.id))
        XCTAssertNil(try secrets.secret(.token, for: config.id))
        XCTAssertNil(model.pipeSession(for: config.id))
    }
}
