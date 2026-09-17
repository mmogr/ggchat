import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// The mock connector with its dials counted, so "the pipe a device paired
/// over is the one it keeps" can be asserted as the absence of a second dial
/// rather than inferred from a session existing.
private final class CountingPipeConnector: PipeConnector, Sendable {
    let inner: MockPipeConnector
    private let dials = Mutex(0)
    private let held = Mutex(false)
    private let pairingsOut = Mutex(0)

    init(registry: LoopbackProviderRegistry, pairings: MockPairings) {
        inner = MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry, pairings: pairings)
    }

    /// How many ordinary dials have gone out.
    var connects: Int {
        dials.withLock { $0 }
    }

    /// Holds every pairing at the gate until ``release()``, so the window a
    /// pairing is out in can be looked into rather than raced for.
    func hold() { held.withLock { $0 = true } }

    func release() { held.withLock { $0 = false } }

    /// How many pairings have reached the gate, released or not.
    var pairingsStarted: Int { pairingsOut.withLock { $0 } }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        dials.withLock { $0 += 1 }
        return try await inner.connect(ticket: ticket, token: token)
    }

    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        pairingsOut.withLock { $0 += 1 }
        while held.withLock({ $0 }) { await Task.yield() }
        return try await inner.pair(pairing: pairing, deviceName: deviceName)
    }
}

/// Everything one of these tests holds on to, as a type rather than a tuple
/// of four.
@MainActor
private struct PairingRig {
    let model: AppModel
    let connector: CountingPipeConnector
    let secrets: InMemorySecrets

    /// What the connector's pairing was scripted with, and what it was asked.
    var pairings: MockPairings { connector.inner.pairings }
}

final class AppModelPairingTests: XCTestCase {
    /// modelpipe's normative vector 1 from `docs/ticket-format-v0.md`.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    private var pairing: String { "\(ticket)-483920" }

    /// The sentence modelpipe writes for a refused code, which is what the
    /// real connector carries into `pairingRefused`.
    private static let refusedSentence =
        "The other machine did not accept that code. It may be wrong, expired or already used, "
        + "so ask for a new one."

    @MainActor
    private func makeModel(
        _ outcome: Result<String, PipeConnectError> = .success("far-machine-key")
    ) -> PairingRig {
        let registry = LoopbackProviderRegistry()
        let secrets = InMemorySecrets()
        let connector = CountingPipeConnector(
            registry: registry, pairings: MockPairings(outcome: outcome))
        let defaults = UserDefaults(suiteName: "AppModelPairingTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        return PairingRig(model: model, connector: connector, secrets: secrets)
    }

    private func pipeConfig() -> ProviderConfig {
        ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
    }

    /// The whole point of the branch: the key is fetched over the pipe, not
    /// read off the other machine's screen and typed in here — and the pipe
    /// it was fetched over is the one the provider goes on using. A second
    /// dial would be a second hole punch for nothing, so the count of
    /// ordinary dials has to stay at zero. It would no longer be a second
    /// endpoint identity: this device keeps one per machine now.
    @MainActor
    func testARedeemedCodeBecomesTheProvidersTokenAndThePipeConnects() async throws {
        let rig = makeModel()
        let (model, secrets) = (rig.model, rig.secrets)
        let config = pipeConfig()

        try await model.addPairedProvider(config, pairing: pairing, ticket: ticket, deviceName: nil)

        XCTAssertEqual(model.providers.map(\.id), [config.id])
        XCTAssertEqual(
            try secrets.secret(.token, for: config.id), "far-machine-key",
            "the key the code was traded for is the token; nothing was carried by hand")
        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), ticket)
        XCTAssertNotNil(model.pipeSession(for: config.id), "pairing ends with the pipe up")
        XCTAssertEqual(
            rig.connector.connects, 0,
            "the pipe the code was redeemed over was hung up and dialled again")
        XCTAssertEqual(model.diagnostics.ticketDigests, [Ticket.digest(ticket)])
    }

    /// A refusal must leave nothing half-added for the next attempt to trip
    /// over, whether that attempt retypes the code or brings a fresh one. And
    /// it has to say where the next attempt starts, which is on the other
    /// machine.
    @MainActor
    func testARefusedCodeAddsNoProviderAndSaysWhy() async throws {
        let rig = makeModel(.failure(.pairingRefused(message: Self.refusedSentence)))
        let (model, secrets) = (rig.model, rig.secrets)
        let config = pipeConfig()

        do {
            try await model.addPairedProvider(config, pairing: pairing, ticket: ticket, deviceName: nil)
            XCTFail("a refused code added a provider")
        } catch let error as PipeConnectError {
            XCTAssertEqual(error, .pairingRefused(message: Self.refusedSentence))
            XCTAssertTrue(
                error.localizedDescription.contains("did not accept that code"), error.localizedDescription)
            XCTAssertTrue(
                error.localizedDescription.contains("gglib remote invite"), error.localizedDescription)
        }

        XCTAssertTrue(model.providers.isEmpty)
        XCTAssertNil(try secrets.secret(.ticket, for: config.id))
        XCTAssertNil(try secrets.secret(.token, for: config.id))
        XCTAssertNil(model.pipeSession(for: config.id))
    }

    /// A pairing takes the longest await in the app — dial, reach the far
    /// machine, spend the code — so the app going to the background under it
    /// is minutes of chance rather than microseconds. The pipe is rightly not
    /// installed, but the provider still has to be left recoverable: a
    /// provider with no status has no pill, and `resumeEveryPipe` dials only
    /// what it already has a status for, so it would be skipped for ever.
    @MainActor
    func testAPairingThatLandsWhileTheAppIsAwayKeepsItsKeyAndItsPill() async throws {
        let rig = makeModel()
        let config = pipeConfig()
        await rig.model.scene(.background).value

        try await rig.model.addPairedProvider(config, pairing: pairing, ticket: ticket, deviceName: nil)

        XCTAssertEqual(
            try rig.secrets.secret(.token, for: config.id), "far-machine-key",
            "the code was spent and the key it bought was thrown away")
        XCTAssertNil(
            rig.model.pipeSession(for: config.id), "a pipe was installed in a backgrounded app")
        XCTAssertEqual(
            rig.model.pipeStatus(for: config.id), .idle,
            "no status, so no pill and no resume: the provider can never be dialled again")
    }

    /// Reconnect is offered on every provider but one dialling already, and a
    /// re-pairing is a dial in all but name: pressing it would dial the
    /// machine being replaced, with the token being replaced, for as long as
    /// the pairing takes.
    @MainActor
    func testReconnectIsNotOfferedWhileAPairingIsOut() async throws {
        let rig = makeModel()
        let config = pipeConfig()
        try rig.model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])
        XCTAssertTrue(rig.model.canReconnect(config.id), "nothing is out yet")

        rig.connector.hold()
        let pairing = Task { [model = rig.model, pairing] in
            try await model.updatePairedProvider(
                config, pairing: pairing, ticket: ticket, deviceName: nil)
        }
        for _ in 0..<500 where rig.connector.pairingsStarted == 0 { await Task.yield() }

        XCTAssertEqual(rig.connector.pairingsStarted, 1, "the pairing never reached the gate")
        XCTAssertFalse(
            rig.model.canReconnect(config.id), "Reconnect stayed live while the pairing was out")

        rig.connector.release()
        try await pairing.value
        XCTAssertTrue(rig.model.canReconnect(config.id), "the flag outlived the pairing")
    }

    // MARK: - This device's name

    /// What the person typed for this device is what the pairing carries. The
    /// provider is called "home", and that names the far machine, not this one.
    @MainActor
    func testTheNameTypedForThisDeviceIsWhatTheRedeemCarries() async throws {
        let rig = makeModel()

        try await rig.model.addPairedProvider(
            pipeConfig(), pairing: pairing, ticket: ticket, deviceName: "Kitchen iPad")

        XCTAssertEqual(rig.pairings.deviceNames, ["Kitchen iPad"])
    }

    /// The mistake this guards against is the natural one: a missing device
    /// name filled in from the provider's. That would put the desktop's own
    /// name in the desktop's list of devices. Missing is nil, and it is also
    /// the empty string a blank field holds, which is what the forms pass;
    /// adding and pairing again are both walked.
    @MainActor
    func testWithNoDeviceNameTheProvidersNameIsNotSentInItsPlace() async throws {
        for missing in [nil, ""] as [String?] {
            let rig = makeModel()
            let config = pipeConfig()

            try await rig.model.addPairedProvider(config, pairing: pairing, ticket: ticket, deviceName: missing)
            try await rig.model.updatePairedProvider(config, pairing: pairing, ticket: ticket, deviceName: missing)

            XCTAssertEqual(
                rig.pairings.deviceNames, [missing, missing], "the provider's name went out as this device's")
        }
    }

    /// Pairing again asks again, because the name is kept nowhere on this
    /// side: it goes out with the pairing and that is the end of it here.
    @MainActor
    func testRePairingCarriesTheNameTypedForThisDevice() async throws {
        let rig = makeModel()
        let config = pipeConfig()
        try rig.model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])

        try await rig.model.updatePairedProvider(
            config, pairing: pairing, ticket: ticket, deviceName: "Kitchen iPad")

        XCTAssertEqual(rig.pairings.deviceNames, ["Kitchen iPad"])
    }
}
