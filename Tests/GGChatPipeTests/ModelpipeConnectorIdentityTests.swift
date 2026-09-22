import GGChatCore
import Modelpipe
import Synchronization
import XCTest

@testable import GGChatPipe

/// What the far machine sees this device as, dial after dial: one endpoint key
/// per machine, kept in a directory this app makes and modelpipe writes into.
///
/// From modelpipe-ffi 0.4.0 the binding names the file and heals it. What is
/// left on this side, and so what is tested here, is which directory a dial
/// carries, that a dial still goes out when there is none, that a refusal
/// this side cannot fix is not dialled again here, and that the connector as
/// it ships really hands the directory over.
///
/// A file of its own beside the other connector suites — what a dial does,
/// what a pairing does, and what a person is shown when one is refused;
/// together they would be over this repo's file-size limit.
final class ModelpipeConnectorIdentityTests: XCTestCase {
    /// modelpipe's normative vector 1, so a refusal here is about the code
    /// under test and not about the input.
    private let realTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    private func connector(
        identities: PipeIdentityFiles? = nil,
        dial: @escaping ModelpipeConnector.Dial
    ) -> ModelpipeConnector {
        ModelpipeConnector(
            sleeper: ImmediateSleeper(), grace: .milliseconds(1), identities: identities, dial: dial)
    }

    /// A directory of this test's own, so that nothing here can write into the
    /// one a real app on this machine keeps its keys in.
    private func temporaryIdentities() -> PipeIdentityFiles {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-connector-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return PipeIdentityFiles(directory: root)
    }

    // MARK: - The device the far machine sees

    /// Every dial carries the one directory this device keeps its keys in,
    /// whichever way the ticket was written down — which is all this can now
    /// assert, because the directory does not depend on the ticket.
    ///
    /// That a machine scanned off a QR code today and typed tomorrow is *one
    /// device* is the binding's rule now, and it is pinned in the binding:
    /// `identity_file_tests::a_shouted_ticket_names_the_same_file`. Nothing in
    /// this package asserts it any more. `BindingTests` pins the name against
    /// a literal, which is a different claim and says so.
    func testEveryDialCarriesTheDirectoryThisDeviceKeepsItsKeysIn() async throws {
        let identities = temporaryIdentities()
        let seen = Mutex<[String?]>([])
        let connector = connector(identities: identities) { _, identityDir in
            seen.withLock { $0.append(identityDir) }
            return FakePipe()
        }

        _ = try await connector.connect(ticket: realTicket, token: "the-key")
        _ = try await connector.connect(ticket: realTicket.uppercased(), token: "the-key")

        // Unwrapped, not compared as optionals: `directoryPath()` is the
        // thing under test here, and `nil == nil` would be a green comparison
        // for a build that had stopped naming a directory at all.
        let expected = try XCTUnwrap(identities.directoryPath())
        let carried = seen.withLock { $0 }
        XCTAssertEqual(carried.count, 2)
        XCTAssertEqual(try XCTUnwrap(carried.first), expected)
        XCTAssertEqual(
            carried.first, carried.last,
            "the same machine was dialled from two places: \(carried)")
    }

    /// With nowhere to keep one, the dial goes out without a key and modelpipe
    /// mints one for this process — which is what every build before this one
    /// did. A phone that cannot write into its own container loses a stable
    /// fingerprint, not the ability to connect.
    func testWithNowhereToKeepAKeyTheDialStillGoesOut() async throws {
        let seen = Mutex<[String?]>([])
        let connector = connector { _, identityDir in
            seen.withLock { $0.append(identityDir) }
            return FakePipe()
        }

        _ = try await connector.connect(ticket: realTicket, token: "the-key")

        XCTAssertEqual(seen.withLock { $0 }, [nil])
    }

    /// A key this device cannot use is thrown away and the dial tried once more
    /// *inside the binding*, so an `MpError.Identity` that reaches this side is
    /// one the discard could not fix: the directory was missing, or the
    /// replacement could not be written. Whatever the cause, dialling again
    /// here would fail the same way for as long as anyone kept trying, so this
    /// side dials once and hands over modelpipe's sentence.
    ///
    /// This is the half of the old retry that did not move: the judgement that
    /// there is nothing left to try.
    func testAnIdentityRefusalIsNotDialledAgainOnThisSide() async throws {
        let identities = temporaryIdentities()
        let attempts = Mutex(0)
        let connector = connector(identities: identities) { _, identityDir in
            attempts.withLock { $0 += 1 }
            throw MpError.Identity(path: (identityDir ?? "nowhere") + "/a-key.key")
        }

        do {
            _ = try await connector.connect(ticket: realTicket, token: "the-key")
            XCTFail("a dial that could not keep an identity produced a session")
        } catch let error as PipeConnectError {
            guard case .dialFailed(let message, let retryable) = error else {
                return XCTFail("expected dialFailed, got \(error)")
            }
            XCTAssertFalse(retryable)
            XCTAssertFalse(message.contains("MpError"), message)
        }

        XCTAssertEqual(
            attempts.withLock { $0 }, 1,
            "the binding had already discarded and retried; this side tried again on top")
    }

    /// And the connector as it ships really hands that directory over, and a
    /// key really lands in it. The dial is a fake closure in every other test,
    /// so without this nothing would notice a shipped build that quietly
    /// dropped the identity and introduced itself afresh on every launch.
    func testTheShippedConnectorKeepsAKeyWhereItSaysItDoes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-shipped-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let identities = PipeIdentityFiles(directory: root)
        let directory = try XCTUnwrap(identities.directoryPath())
        let connector = ModelpipeConnector.live(identities: identities)

        let session = try await connector.connect(ticket: realTicket, token: "a-key")
        await session.shutdown()

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory).count, 1,
            "the shipped dial kept no key in \(directory)")
    }
}
