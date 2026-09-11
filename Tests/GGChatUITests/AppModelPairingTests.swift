import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A redeemer with a fixed answer, so the app model's pairing path can be
/// walked without a machine on the other end of anything. It keeps the device
/// names it was handed, which is all a test here reads back.
private final class FixedRedeemer: PairingRedeemer, Sendable {
    private let outcome: Result<String, PairingError>
    private let names = Mutex<[String?]>([])

    init(_ outcome: Result<String, PairingError>) {
        self.outcome = outcome
    }

    var deviceNames: [String?] {
        names.withLock { $0 }
    }

    func redeem(code: String, deviceName: String?, through baseURL: URL) async throws -> String {
        names.withLock { $0.append(deviceName) }
        return try outcome.get()
    }
}

final class AppModelPairingTests: XCTestCase {
    /// modelpipe's normative vector 1 from `docs/ticket-format-v0.md`.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(_ redeemer: FixedRedeemer) -> (AppModel, InMemorySecrets) {
        let registry = LoopbackProviderRegistry()
        let secrets = InMemorySecrets()
        let defaults = UserDefaults(suiteName: "AppModelPairingTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            redeemer: redeemer, diagnostics: Diagnostics(defaults: defaults),
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
        let (model, secrets) = makeModel(FixedRedeemer(.success("far-machine-key")))
        let config = pipeConfig()

        try await model.addPairedProvider(config, ticket: ticket, code: "483920", deviceName: nil)

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
        let (model, secrets) = makeModel(FixedRedeemer(.failure(.refused)))
        let config = pipeConfig()

        do {
            try await model.addPairedProvider(config, ticket: ticket, code: "000000", deviceName: nil)
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

    // MARK: - This device's name

    /// What the person typed for this device is what the redeem carries. The
    /// provider is called "home", and that names the far machine, not this one.
    @MainActor
    func testTheNameTypedForThisDeviceIsWhatTheRedeemCarries() async throws {
        let redeemer = FixedRedeemer(.success("far-machine-key"))
        let (model, _) = makeModel(redeemer)

        try await model.addPairedProvider(pipeConfig(), ticket: ticket, code: "483920", deviceName: "Kitchen iPad")

        XCTAssertEqual(redeemer.deviceNames, ["Kitchen iPad"])
    }

    /// The mistake this guards against is the natural one: a missing device
    /// name filled in from the provider's. That would put the desktop's own
    /// name in the desktop's list of devices. Missing is nil, and it is also
    /// the empty string a blank field holds, which is what the forms pass;
    /// adding and pairing again are both walked.
    @MainActor
    func testWithNoDeviceNameTheProvidersNameIsNotSentInItsPlace() async throws {
        for missing in [nil, ""] as [String?] {
            let redeemer = FixedRedeemer(.success("far-machine-key"))
            let (model, _) = makeModel(redeemer)
            let config = pipeConfig()

            try await model.addPairedProvider(config, ticket: ticket, code: "483920", deviceName: missing)
            try await model.updatePairedProvider(config, ticket: ticket, code: "483920", deviceName: missing)

            XCTAssertEqual(
                redeemer.deviceNames, [missing, missing], "the provider's name went out as this device's")
        }
    }

    /// Pairing again asks again, because the name is kept nowhere on this
    /// side: it goes out with the redeem and that is the end of it here.
    @MainActor
    func testRePairingCarriesTheNameTypedForThisDevice() async throws {
        let redeemer = FixedRedeemer(.success("far-machine-key"))
        let (model, _) = makeModel(redeemer)
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])

        try await model.updatePairedProvider(config, ticket: ticket, code: "483920", deviceName: "Kitchen iPad")

        XCTAssertEqual(redeemer.deviceNames, ["Kitchen iPad"])
    }
}
