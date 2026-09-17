import GGChatCore
import XCTest

@testable import GGChatPipe

/// Where this device's endpoint keys live, and what this app is allowed to do
/// to them: name one per machine, and throw one away. What is inside a file is
/// modelpipe's, and nothing here reads one.
final class PipeIdentityFilesTests: XCTestCase {
    /// modelpipe's normative vectors 1 and 3, so that "another ticket" is a
    /// string a dial would accept rather than one invented here.
    private let oneTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let anotherTicket =
        "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaicaajcaainxaaaaaaaaaaaaaaaaaaach4qaabstehw"

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-identity-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func files() -> PipeIdentityFiles {
        PipeIdentityFiles(directory: root.appending(path: "pipe-identities"))
    }

    // MARK: - One name per machine

    /// The same machine is the same file however its ticket was written down:
    /// typed in lower case, scanned off a QR code in upper case, or read back
    /// from a provider a version of this app stored before the reader folded
    /// the case for it. A device that got a new key each time it scanned
    /// rather than typed would be a new device to the far machine each time.
    func testOneMachineIsOneFileWhateverCaseItsTicketIsIn() throws {
        let identities = files()

        let typed = try XCTUnwrap(identities.path(forTicket: oneTicket))
        let scanned = try XCTUnwrap(identities.path(forTicket: oneTicket.uppercased()))

        XCTAssertEqual(typed, scanned)
        XCTAssertEqual(
            URL(filePath: typed).lastPathComponent, Ticket.digest(oneTicket) + ".key",
            "the file is named by the digest a provider already stores")
        XCTAssertFalse(
            typed.contains(oneTicket), "the ticket itself is in the path: \(typed)")
    }

    /// Two tickets are two files. Two machines are two endpoints and an
    /// endpoint is a key: iroh's relay allows one live connection per endpoint
    /// id, so a phone holding a pipe to two desktops with one key would take
    /// the relay away from the first every time it dialled the second.
    ///
    /// These two vectors happen to name the *same* endpoint written two ways,
    /// with addresses and without, which is the edge of what the ticket can
    /// tell this app: the file is named by the string a provider stores, and
    /// reading an endpoint id out of it would be the ticket parse that lives
    /// in modelpipe. So re-adding one machine from a differently written
    /// ticket introduces this device to it afresh — the same answer as any
    /// other change of endpoint, and the reason the far side records a
    /// fingerprint rather than pinning one.
    func testTwoTicketsGetTwoFiles() throws {
        let identities = files()

        let first = try XCTUnwrap(identities.path(forTicket: oneTicket))
        let second = try XCTUnwrap(identities.path(forTicket: anotherTicket))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(
            URL(filePath: first).deletingLastPathComponent(),
            URL(filePath: second).deletingLastPathComponent(),
            "both belong to this app's own directory")
    }

    // MARK: - The directory

    /// Made on the way to naming the first file, readable only by this user,
    /// and out of the backup: a restored phone is a different device and has
    /// to look like one, or two phones answer to one name on the far machine.
    func testTheDirectoryIsMadePrivateAndKeptOutOfTheBackup() throws {
        let identities = files()

        _ = try XCTUnwrap(identities.path(forTicket: oneTicket))

        let directory = identities.directory
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let mode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: directory.path(percentEncoded: false))[.posixPermissions]
                as? NSNumber)
        XCTAssertEqual(
            mode.int16Value & 0o077, 0,
            "somebody else on this machine can read the keys: mode \(String(mode.int16Value, radix: 8))")
        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true, "the keys would ride a backup onto a second device")
    }

    /// The other half of the headline contract: with nowhere to keep a key
    /// the answer is `nil`, and the connector dials without one rather than
    /// refusing. Forced by standing a regular file where the directory
    /// belongs, which is how `createDirectory` fails without a fake.
    func testWithNowhereToKeepAKeyThereIsNoPath() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identities = files()
        FileManager.default.createFile(
            atPath: identities.directory.path(percentEncoded: false),
            contents: Data("not a directory".utf8))

        XCTAssertNil(identities.path(forTicket: oneTicket))
    }

    /// Naming a file does not make one: modelpipe writes the key itself, on
    /// the first dial that uses the path.
    func testNamingAFileDoesNotCreateIt() throws {
        let path = try XCTUnwrap(files().path(forTicket: oneTicket))

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - A key half written

    /// modelpipe creates the file and writes the key in two steps, so a
    /// process killed between them leaves nothing in it — and an empty file is
    /// not a key, so every later dial to that machine is refused for good.
    /// Emptiness is the only judgement this app makes about the contents.
    func testAFileOfNothingIsThrownAwayBeforeItIsHandedOver() throws {
        let identities = files()
        let path = try XCTUnwrap(identities.path(forTicket: oneTicket))
        FileManager.default.createFile(atPath: path, contents: Data())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        _ = try XCTUnwrap(identities.path(forTicket: oneTicket))

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: path),
            "an empty file is a key half written, and modelpipe refuses it for ever")
    }

    /// Anything else is left exactly as it was found. A key this app rewrote,
    /// re-encoded or "tidied" would be a second opinion about modelpipe's own
    /// file format, which is the duplication this seam exists to refuse.
    func testAFileWithAKeyInItIsLeftByteForByte() throws {
        let identities = files()
        let path = try XCTUnwrap(identities.path(forTicket: oneTicket))
        let stored = Data("aznmoyaqvvqgfrtdjxnwcejbjrp72o4mrywtnjxqqxwpxyrymxaa\n".utf8)
        FileManager.default.createFile(atPath: path, contents: stored)

        _ = try XCTUnwrap(identities.path(forTicket: oneTicket))

        XCTAssertEqual(FileManager.default.contents(atPath: path), stored)
    }

    // MARK: - Throwing one away

    /// The way out of a key this device cannot use. It says whether there was
    /// one, because a caller that dialled again after removing nothing would
    /// meet the same refusal for as long as it kept trying.
    func testDiscardRemovesTheKeyAndSaysWhetherThereWasOne() throws {
        let identities = files()
        let path = try XCTUnwrap(identities.path(forTicket: oneTicket))
        FileManager.default.createFile(atPath: path, contents: Data("not a key".utf8))

        XCTAssertTrue(identities.discard(at: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertFalse(identities.discard(at: path), "there was nothing left to throw away")
    }
}
