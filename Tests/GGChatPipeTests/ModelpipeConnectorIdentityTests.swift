import GGChatCore
import Modelpipe
import Synchronization
import XCTest

@testable import GGChatPipe

/// What the far machine sees this device as, dial after dial: one endpoint
/// key per machine, kept in a file modelpipe writes, and thrown away only
/// when it is the thing stopping a dial.
///
/// A file of its own beside the other two connector suites, which are what a
/// dial does and what a pairing does; together they would be over this repo's
/// file-size limit.
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

    /// Every dial to one machine carries the same key, so the endpoint it
    /// recorded as this device paired is the one still dialling it on the next
    /// launch. Whichever way the ticket was written down: the path is
    /// built from the canonical form the reader hands back, not from what was
    /// pasted, so a machine scanned off a QR code today and typed tomorrow is
    /// one device rather than two.
    func testEveryDialToOneMachineCarriesTheSameKey() async throws {
        let identities = temporaryIdentities()
        let seen = Mutex<[String?]>([])
        let connector = connector(identities: identities) { _, identityPath in
            seen.withLock { $0.append(identityPath) }
            return FakePipe()
        }

        _ = try await connector.connect(ticket: realTicket, token: "the-key")
        _ = try await connector.connect(ticket: realTicket.uppercased(), token: "the-key")

        let carried = seen.withLock { $0 }
        XCTAssertEqual(carried.count, 2)
        XCTAssertEqual(carried.first, identities.path(forTicket: realTicket))
        XCTAssertEqual(
            carried.first, carried.last,
            "the same machine was dialled as two devices: \(carried)")
    }

    /// With nowhere to keep one, the dial goes out without a key and modelpipe
    /// mints one for this process — which is what every build before this one
    /// did. A phone that cannot write into its own container loses a stable
    /// fingerprint, not the ability to connect.
    func testWithNowhereToKeepAKeyTheDialStillGoesOut() async throws {
        let seen = Mutex<[String?]>([])
        let connector = connector { _, identityPath in
            seen.withLock { $0.append(identityPath) }
            return FakePipe()
        }

        _ = try await connector.connect(ticket: realTicket, token: "the-key")

        XCTAssertEqual(seen.withLock { $0 }, [nil])
    }

    /// modelpipe refuses a key file it cannot use and asks for it to be
    /// removed or replaced, which is not something anybody can do on a phone —
    /// so a dial that meets that refusal throws the file away itself and dials
    /// once more. The cost is this device's fingerprint on that machine, which
    /// records fingerprints rather than pinning them; the alternative is a
    /// provider that can never connect again.
    func testAKeyThisDeviceCannotUseIsThrownAwayAndTheDialTriedAgain() async throws {
        let identities = temporaryIdentities()
        let path = try XCTUnwrap(identities.path(forTicket: realTicket))
        FileManager.default.createFile(atPath: path, contents: Data("not a key at all".utf8))
        let attempts = Mutex(0)
        let connector = connector(identities: identities) { _, _ in
            let attempt = attempts.withLock { count -> Int in
                count += 1
                return count
            }
            if attempt == 1 { throw MpError.Identity(path: path) }
            return FakePipe()
        }

        _ = try await connector.connect(ticket: realTicket, token: "the-key")

        XCTAssertEqual(attempts.withLock { $0 }, 2, "the dial was not tried again")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path),
            "the key that could not be used is still there to refuse the next dial too")
    }

    /// Once, though. With no file to throw away the refusal is about the path
    /// or the directory rather than the key, and dialling again would fail the
    /// same way for as long as anyone kept trying; the person gets modelpipe's
    /// sentence instead.
    func testAnIdentityRefusalWithNoKeyToThrowAwayIsNotRetried() async throws {
        let identities = temporaryIdentities()
        let attempts = Mutex(0)
        let connector = connector(identities: identities) { _, identityPath in
            attempts.withLock { $0 += 1 }
            throw MpError.Identity(path: identityPath ?? "nowhere")
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
            "there was nothing to throw away, so trying again could only fail the same way")
    }

    /// And the connector as it ships really hands that path over. The dial is
    /// a fake closure in every other test, so without this nothing would
    /// notice a shipped build that quietly dropped the identity and introduced
    /// itself afresh on every launch.
    func testTheShippedConnectorKeepsAKeyWhereItSaysItDoes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-shipped-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let identities = PipeIdentityFiles(directory: root)
        let expected = try XCTUnwrap(identities.path(forTicket: realTicket))
        let connector = ModelpipeConnector.live(identities: identities)

        let session = try await connector.connect(ticket: realTicket, token: "a-key")
        await session.shutdown()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expected),
            "the shipped dial kept no key at \(expected)")
    }
}
