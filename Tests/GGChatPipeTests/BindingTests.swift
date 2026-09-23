import GGChatCore
import GGChatPipe
import Modelpipe
import XCTest

/// That the binding is really here, and that its four status values still mean
/// what this app thinks they mean.
///
/// The link is the point of the first test. Everything else in this repository
/// is Swift compiled from source; `Modelpipe` is a binary xcframework fetched
/// at resolve time and checked against a uniffi checksum that is only verified
/// on first use. A mismatched pair does not fail the build — it traps at the
/// first call, on a device, in front of a person. So something has to make a
/// call across the boundary on every CI run, and this is it.
final class BindingTests: XCTestCase {
    /// modelpipe's normative vector 1: a ticket the binding accepts, naming an
    /// endpoint nobody is, so a dial through it binds a local port and reaches
    /// nothing.
    private static let vector =
        "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// A ticket the far side never has to see refused, because it is refused
    /// here. Reaching this error means the Rust ran: the string crossed the
    /// boundary, a `uniffi` error came back, and it arrived as a Swift enum.
    func testTheBindingIsLinkedAndAnswersAcrossTheBoundary() async {
        do {
            _ = try await mpConnect(ticket: "not-a-ticket", options: MpConnectOptions())
            XCTFail("a string that is not a ticket was accepted as one")
        } catch let error as MpError {
            guard case .BadTicket = error else {
                return XCTFail("expected BadTicket, got \(error.message())")
            }
            XCTAssertFalse(
                error.message().isEmpty,
                "an error the app may have to show a person came back with nothing to say")
        } catch {
            XCTFail("the binding threw something that is not an MpError: \(error)")
        }
    }

    /// Pairing waits for the far machine before it spends the code, and this
    /// is the real `mpPair` proving it offline.
    ///
    /// The ticket is modelpipe's normative vector 1, which names an endpoint
    /// that does not exist; discovery and port mapping are off so nothing is
    /// asked of the network beyond the relay dial, and the wait is 150 ms so the test
    /// costs a fraction of a second. Reaching `Unreached` means the string
    /// parsed, a pipe was dialled, the wait ran out — and the code was never
    /// presented. A redeem sent into that gap is answered `502` by the
    /// connecting side, which never had a backend to reach; that spends the
    /// one-time code on nothing and needs a fresh `gglib remote invite`.
    func testPairingWaitsForTheFarMachineBeforeSpendingTheCode() async {
        var options = MpConnectOptions()
        options.discovery = false
        options.portMapping = false
        do {
            _ = try await mpPair(
                pairing: "\(Self.vector)-483920", label: "a test", options: options, reachWithinMs: 150)
            XCTFail("a machine that does not exist accepted a pairing code")
        } catch let error as MpPairError {
            guard case .Unreached = error else {
                return XCTFail("expected Unreached, got \(error.message())")
            }
            XCTAssertTrue(
                error.isRetryable(),
                "a machine that did not answer in time is one that may answer next time")
            XCTAssertFalse(
                error.message().isEmpty,
                "an error the app has to show a person came back with nothing to say")
        } catch {
            XCTFail("the binding threw something that is not an MpPairError: \(error)")
        }
    }

    /// A device that keeps its endpoint key is the same device to the far
    /// machine every time, and this is the real binding saying so: two dials
    /// through one identity file report one peer id, and a dial with no file
    /// reports another. That is the whole of D6 — the endpoint a serving
    /// machine records as this device pairs is one that still exists after the
    /// app is quit.
    ///
    /// Offline: modelpipe's normative vector 1 names an endpoint that does not
    /// exist and carries no transport addresses, and discovery and port
    /// mapping are both off, so nothing is asked of the network beyond the
    /// relay dial — the same as the pairing test above. `mpConnect` returns
    /// once the local port is bound rather than once the far machine answers,
    /// which is what makes this cheap enough to run on every build.
    func testADeviceThatKeepsItsKeyIsTheSameDeviceNextTime() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-binding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let directory = root.path(percentEncoded: false)

        func peerId(keptIn path: String?) async throws -> String {
            var options = MpConnectOptions(identityDir: path)
            options.discovery = false
            // Both off, or the claim above is not true: port mapping
            // defaults to on and talks to the gateway over UPnP/NAT-PMP/PCP.
            options.portMapping = false
            let pipe = try await mpConnect(ticket: Self.vector, options: options)
            let id = pipe.peerId()
            await pipe.shutdown()
            return id
        }

        let first = try await peerId(keptIn: directory)
        let second = try await peerId(keptIn: directory)
        let keepingNothing = try await peerId(keptIn: nil)

        XCTAssertEqual(first, second, "one identity directory, and yet two devices")
        XCTAssertNotEqual(
            first, keepingNothing,
            "a dial that kept no key reported the same device as one that kept a key, "
                + "so this test cannot tell the two apart and proves nothing")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory).count, 1,
            "modelpipe was handed a directory and kept exactly one key in it")
    }

    /// The two enums match one for one, and this is what keeps that true. It
    /// is written out rather than looped so that a case added on either side
    /// is a compile error here and not a silent gap.
    func testEveryPipeStatusCrossesUnchanged() {
        XCTAssertEqual(PipeStatus(MpPipeStatus.idle), .idle)
        XCTAssertEqual(PipeStatus(MpPipeStatus.relayed), .relayed)
        XCTAssertEqual(PipeStatus(MpPipeStatus.direct), .direct)
        XCTAssertEqual(PipeStatus(MpPipeStatus.closed), .closed)
    }

    /// `isConnected` is the app's own judgement, not the binding's, and the
    /// pipe path depends on relayed counting as connected: a relayed pipe
    /// works, and its traffic is no more readable than a direct one's.
    func testARelayedPipeCountsAsConnected() {
        XCTAssertTrue(PipeStatus(MpPipeStatus.relayed).isConnected)
        XCTAssertTrue(PipeStatus(MpPipeStatus.direct).isConnected)
        XCTAssertFalse(PipeStatus(MpPipeStatus.idle).isConnected)
        XCTAssertFalse(PipeStatus(MpPipeStatus.closed).isConnected)
    }

    /// The name of the key file, asserted from both sides of the boundary
    /// against the same literal, with neither side computing it from the
    /// other.
    ///
    /// This is what holds every already-paired device in place across the
    /// upgrade. Until modelpipe-ffi 0.4.0 this app named the file
    /// `Ticket.digest(canonicalTicket) + ".key"`; from 0.4.0 the binding
    /// names it, hashing `Display` of the ticket it parsed. If those two
    /// disagree, every phone looks for a key file that is no longer written,
    /// mints a fresh endpoint, and introduces itself to its desktop as a
    /// stranger — with no build failure and no log line.
    ///
    /// So Swift's half here stands in for what a shipped build wrote, and it
    /// is only a fair stand-in because the argument is the canonical ticket,
    /// which is the only thing any call site ever passed
    /// (`ModelpipeConnector` and `ModelpipeConnector+Pairing` both read
    /// through `mpReadPairing` first, at every commit that ever reached
    /// `main`).
    ///
    /// **What this does not see:** the two are not the same transform.
    /// `Ticket.digest` folds ASCII case and hashes its argument; the binding
    /// parses and hashes the canonical form, which also sorts addresses and
    /// drops an address tag it does not know. On a ticket that is already
    /// canonical — this vector is — they coincide, so this test would pass
    /// under either. It pins the constant, not the equivalence of the rules.
    ///
    /// `0382e9033d890983` is the digest of modelpipe's normative vector 1,
    /// which is also modelpipe-ffi's own `GOOD_TICKET`, so the same constant
    /// is asserted on the Rust side by `identity_file_tests`. It is written
    /// out here rather than derived, because a test that computed the expected
    /// name from `Ticket.digest` would pass whatever `Ticket.digest` did.
    func testTheKeyFilesNameIsTheSameRuleOnBothSidesOfTheBoundary() async throws {
        let expected = "0382e9033d890983.key"

        // Side one: the rule a shipped 0.3.x build named the file by. A
        // failure here does not orphan anyone by itself — it means this
        // stand-in has stopped representing what those builds wrote, and so
        // has stopped being evidence for side two.
        XCTAssertEqual(
            Ticket.digest(Self.vector) + ".key", expected,
            "Swift's digest moved, so it no longer stands for what 0.3.x wrote")

        // Side two: what the binding actually writes, having parsed the
        // ticket itself. No Swift-computed *name* reaches this: the ticket
        // and the directory cross, and the binding derives the name from the
        // first. That is what makes it independent evidence rather than a
        // restatement of side one.
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let directory = root.path(percentEncoded: false)

        var options = MpConnectOptions(identityDir: directory)
        options.discovery = false
        options.portMapping = false
        let pipe = try await mpConnect(ticket: Self.vector, options: options)
        await pipe.shutdown()

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory), [expected],
            "the binding's name for this ticket's key file moved, and every device "
                + "paired by a 0.3.x build is looking for the old one")
    }

    /// A key file this device cannot use is thrown away and the dial tried
    /// once more — by the binding, which is the only layer that names the
    /// file, and so the only one that can find the file to remove.
    ///
    /// This is the other half of what moved across the seam at modelpipe-ffi
    /// 0.4.0, and it is load-bearing in the way the name is. The tests that
    /// asserted it here went down with the code they were written against. If
    /// the binding ever stops, nothing in this package would notice: the
    /// manifest takes any 0.4.x, the suite stays green, and a phone whose key
    /// file was left empty by a process killed mid-write gets a permanent
    /// `dialFailed` for that machine, whose only remedy is deleting a file a
    /// phone does not offer anybody.
    ///
    /// Empty rather than garbage because that is the case a crash actually
    /// produces, and it is the one ggchat's own `discardIfEmpty` existed for.
    /// Offline, like the tests above it: the vector names an endpoint nobody
    /// is, and `mpConnect` returns once the local port is bound.
    func testAKeyThisDeviceCannotUseIsThrownAwayAndTheDialTriedAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-heal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let directory = root.path(percentEncoded: false)
        let key = root.appending(path: "0382e9033d890983.key").path(percentEncoded: false)

        // A key half written: the file exists and holds nothing, which is not
        // a key, and which every later dial to this machine used to be
        // refused over for good.
        XCTAssertTrue(FileManager.default.createFile(atPath: key, contents: Data()))
        XCTAssertEqual(
            FileManager.default.contents(atPath: key), Data(),
            "the file this test is about was not empty to begin with")

        var options = MpConnectOptions(identityDir: directory)
        options.discovery = false
        options.portMapping = false
        let pipe = try await mpConnect(ticket: Self.vector, options: options)
        await pipe.shutdown()

        // The name first: if it moved, the probe file below was never the one
        // this dial would look at, and "still empty" would be the wrong thing
        // to report.
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory), ["0382e9033d890983.key"],
            "the binding is not naming this ticket's key file what it named it before")
        let healed = try XCTUnwrap(FileManager.default.contents(atPath: key))
        XCTAssertFalse(
            healed.isEmpty,
            "the binding dialled over a key file of nothing instead of replacing it")
    }
}
