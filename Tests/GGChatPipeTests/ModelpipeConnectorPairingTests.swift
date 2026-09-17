import GGChatCore
import Modelpipe
import Synchronization
import XCTest

@testable import GGChatPipe

/// What the connector does with a pairing string, driven by a fake `Pair`
/// closure so none of it needs a network, a code or a far machine.
///
/// A file of its own beside `ModelpipeConnectorTests`, which is what a dial
/// does; together they would be over this repo's file-size limit.
final class ModelpipeConnectorPairingTests: XCTestCase {
    /// modelpipe's normative vector 1, so a refusal here is about the code
    /// under test and not about the input.
    private let realTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// A connector whose pairing is a fake, and whose dial fails the test if
    /// anything reaches it: keeping the paired pipe means never dialling.
    private func pairingConnector(
        dial: @escaping ModelpipeConnector.Dial = { _, _ in
            XCTFail("the paired pipe was hung up and a second dial went out")
            return FakePipe()
        },
        pairing: @escaping ModelpipeConnector.Pair
    ) -> ModelpipeConnector {
        ModelpipeConnector(sleeper: ImmediateSleeper(), grace: .milliseconds(1), dial: dial, pairing: pairing)
    }

    /// D2, and the reason `mpPair` hands the pipe back at all: the pipe the
    /// code was redeemed over is the provider's first session. A second dial
    /// would be a second hole punch for nothing — and, before this device
    /// kept an endpoint key per machine, a second identity as well, which is
    /// the half of this rationale that has since stopped being true.
    func testThePipeTheCodeWasRedeemedOverIsTheSession() async throws {
        let connector = pairingConnector { _, _, _ in
            .init(
                pipe: FakePipe(baseUrl: "http://127.0.0.1:49333/v1"), apiKey: "far-machine-key",
                device: "Kitchen iPad")
        }

        let paired = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: "Kitchen iPad")

        XCTAssertEqual(paired.session?.baseURL.absoluteString, "http://127.0.0.1:49333/v1")
        XCTAssertEqual(paired.token, "far-machine-key")
        XCTAssertEqual(paired.device, "Kitchen iPad", "the name the far machine holds the key under was dropped")
    }

    /// The whole pairing string goes to modelpipe, which owns the split; the
    /// label is what the person typed for this device, trimmed, and absent
    /// rather than empty when they typed nothing.
    func testTheLabelRidesAsGivenAndABlankOneIsNotSent() async throws {
        let seen = Mutex<[(String, String?)]>([])
        let connector = pairingConnector { pairing, label, _ in
            seen.withLock { $0.append((pairing, label)) }
            return .init(pipe: FakePipe(), apiKey: "far-machine-key", device: "this device")
        }

        _ = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: "  Kitchen iPad ")
        _ = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: "  \n")
        _ = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: nil)

        let calls = seen.withLock { $0 }
        XCTAssertEqual(calls.map(\.0), Array(repeating: "\(realTicket)-483920", count: 3))
        XCTAssertEqual(calls.map(\.1), ["Kitchen iPad", nil, nil])
    }

    /// A pairing dials, so it carries the same endpoint key a later dial to
    /// that machine will: the fingerprint the far machine records beside the
    /// key as it mints it is then the device that goes on chatting through the
    /// pipe, rather than one that existed for the length of the exchange.
    func testAPairingIsMadeAsTheDeviceThatWillDialLater() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-pairing-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let identities = PipeIdentityFiles(directory: root)
        let seen = Mutex<[String?]>([])
        let connector = ModelpipeConnector(
            sleeper: ImmediateSleeper(), grace: .milliseconds(1), identities: identities,
            dial: { _, _ in FakePipe() },
            pairing: { _, _, identityPath in
                seen.withLock { $0.append(identityPath) }
                return .init(pipe: FakePipe(), apiKey: "far-machine-key", device: "this device")
            })

        _ = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: nil)

        XCTAssertEqual(
            seen.withLock { $0 }, [identities.path(forTicket: realTicket)],
            "the pairing introduced this device by a name no later dial will use")
    }

    /// What modelpipe says about a string that is not a pairing string.
    private static let unreadable = MpPairError.BadPairingString(
        reason: "the part before the code is not a ticket")

    /// A string this app cannot read is handed over with no key rather than
    /// refused here: modelpipe is about to read the same string and refuse it
    /// in its own words, and a refusal written here as well would be the
    /// second copy of a sentence this seam exists to keep in one place.
    func testAPairingStringThatCannotBeReadIsStillModelpipesToRefuse() async {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-pairing-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let seen = Mutex<[String?]>([])
        let connector = ModelpipeConnector(
            sleeper: ImmediateSleeper(), grace: .milliseconds(1),
            identities: PipeIdentityFiles(directory: root),
            dial: { _, _ in FakePipe() },
            pairing: { _, _, identityPath in
                seen.withLock { $0.append(identityPath) }
                throw Self.unreadable
            })

        do {
            _ = try await connector.pair(pairing: "nope-483920", deviceName: nil)
            XCTFail("a string that is not a pairing string paired")
        } catch let error as PipeConnectError {
            guard case .dialFailed(let message, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(message, Self.unreadable.message())
        } catch {
            XCTFail("\(error)")
        }

        XCTAssertEqual(seen.withLock { $0 }, [nil], "a key was named for a machine nothing could identify")
    }

    /// The key is the one thing here worth stealing, and the session is the
    /// object the app logs the base URL of.
    func testThePairedSessionIsNotCarryingTheKey() async throws {
        let connector = pairingConnector { _, _, _ in
            .init(pipe: FakePipe(), apiKey: "far-machine-key", device: "this device")
        }

        let paired = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: nil)

        XCTAssertFalse("\(paired.session as Any)".contains("far-machine-key"))
    }

    /// A pipe that came up somewhere the app will not send a request is hung
    /// up, but the key still comes back. The code was spent to mint it, and
    /// throwing it away would send the person to the other machine for a
    /// fresh invite to fix something on this one.
    func testAPairedPipeThatIsRefusedStillHandsTheKeyBack() async throws {
        let pipe = FakePipe(baseUrl: "http://192.168.1.4:8080/v1")
        let connector = pairingConnector { _, _, _ in
            .init(pipe: pipe, apiKey: "far-machine-key", device: "this device")
        }

        let paired = try await connector.pair(pairing: "\(realTicket)-483920", deviceName: nil)

        XCTAssertNil(paired.session, "a pipe off loopback was kept as the session")
        XCTAssertEqual(paired.token, "far-machine-key", "the key was thrown away and the code spent for nothing")
        XCTAssertEqual(pipe.shutdownCount, 1, "a pipe nothing can use was left up")
    }

    /// D3: a refused code is the one pairing failure with somewhere to send
    /// the person, so it keeps a case of its own — and the case is what lets
    /// the line naming what to run on the other machine be added to
    /// modelpipe's sentence.
    func testARefusedCodeKeepsItsOwnCaseAndSaysWhereToGetANewOne() async {
        let refusal = ModelpipeConnector.refusal(for: .Refused)

        guard case .pairingRefused(let message) = refusal else {
            return XCTFail("a refused code was reported as something else: \(refusal)")
        }
        XCTAssertEqual(message, MpPairError.Refused.message(), "the sentence was written here instead of upstream")
        XCTAssertTrue(
            refusal.localizedDescription.contains("gglib remote invite"),
            "nothing told the person where the next attempt starts: \(refusal.localizedDescription)")
        XCTAssertFalse(refusal.isRetryable, "a spent code was offered as worth retrying")
    }

    /// The mapping is exhaustive and written out rather than looped, so a
    /// case modelpipe adds is a compile error rather than a sentence nobody
    /// wrote. What every case owes is a sentence with none of the binding's
    /// own rendering in it: `MpPairError.errorDescription` is
    /// `String(reflecting:)`, so one allowed through unmapped puts
    /// `modelpipe_ffi.MpPairError.Unreached(why: …)` on a person's screen.
    func testEveryPairingErrorArrivesAsASentenceAndNotADebugRendering() {
        let errors: [MpPairError] = [
            .NoCode,
            .BadPairingString(reason: "the part before the code is not a ticket"),
            .Dial(reason: "the port is taken", retryable: true),
            .Unreached(why: .TimedOut(withinMs: 150)),
            .Refused,
            .Exchange(reason: "the connection was reset"),
            .Unexpected(detail: "no api_key"),
            .Unknown(detail: "Grown(…)"),
        ]
        for error in errors {
            let sentence = ModelpipeConnector.refusal(for: error).errorDescription ?? ""
            XCTAssertFalse(sentence.isEmpty, "\(error) has nothing to say")
            XCTAssertFalse(sentence.contains("MpPairError"), sentence)
            // The module is `Modelpipe`, so `String(reflecting:)` renders
            // `Modelpipe.MpPairError…`. Looking for `modelpipe_ffi`, the Rust
            // crate's name, is an assertion that can never fire.
            XCTAssertFalse(sentence.contains("Modelpipe."), sentence)
            XCTAssertTrue(sentence.contains(error.message()), "the sentence is not the binding's: \(sentence)")
        }
    }

    /// A machine that was asleep may answer next time, and the binding is the
    /// thing that knows which pairing failures are like that.
    func testThePairingRetryabilityIsTheBindings() {
        let unreached = MpPairError.Unreached(why: .TimedOut(withinMs: 150))
        XCTAssertEqual(
            ModelpipeConnector.refusal(for: unreached).isRetryable, unreached.isRetryable(),
            "retryability was decided here instead of being carried from the binding")
        XCTAssertTrue(unreached.isRetryable(), "the binding now calls a timed-out pairing not worth repeating")
    }

    /// The other arm of the mapping answers `false` outright rather than
    /// asking the binding, because these three are failures nobody gets past
    /// by trying again: a string with no code in it, a string that is not a
    /// pairing string, and an answer that was not a pairing answer. Both arms
    /// agree with the binding today and no test can tell them apart on that,
    /// so what this pins is the agreement — a release that changes its mind
    /// fails here, at the release that changes it, rather than quietly
    /// offering a retry that cannot work.
    func testTheFailuresNoRetryCanFixAgreeWithTheBinding() {
        let hopeless: [MpPairError] = [
            .NoCode,
            .BadPairingString(reason: "the part before the code is not a ticket"),
            .Unexpected(detail: "no api_key"),
        ]
        for error in hopeless {
            XCTAssertEqual(
                ModelpipeConnector.refusal(for: error).isRetryable, error.isRetryable(),
                "retryability was decided here instead of being carried from the binding: \(error)")
            XCTAssertFalse(
                error.isRetryable(),
                "the binding now calls this worth repeating: revisit the arm the case sits in")
        }
    }
}
