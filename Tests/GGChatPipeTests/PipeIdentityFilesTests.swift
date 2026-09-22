import XCTest

@testable import GGChatPipe

/// Where this device's endpoint keys live, and the only thing this app still
/// does to them: make the directory, privately and out of the backup, and name
/// it.
///
/// Naming the file inside it, throwing away one this device cannot use, and
/// judging one half written all moved into the binding at modelpipe-ffi 0.4.0,
/// where the ticket that decides the name is already parsed. What is inside a
/// file was never this app's business and still is not.
final class PipeIdentityFilesTests: XCTestCase {
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

    /// Made on the way to being named, readable only by this user, and out of
    /// the backup: a restored phone is a different device and has to look like
    /// one, or two phones answer to one name on the far machine.
    ///
    /// These two are why the directory stays on this side of the seam at all.
    /// Rust can create a directory but not portably create it `0o700` in the
    /// same step, and `isExcludedFromBackup` is a Foundation resource value
    /// with no equivalent it could set.
    func testTheDirectoryIsMadePrivateAndKeptOutOfTheBackup() throws {
        let identities = files()

        _ = try XCTUnwrap(identities.directoryPath())

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

    /// The other half of the headline contract: with nowhere to keep a key the
    /// answer is `nil`, and the connector dials without one rather than
    /// refusing. Forced by standing a regular file where the directory
    /// belongs, which is how `createDirectory` fails without a fake.
    ///
    /// `nil` and not the path of a directory that is not there: modelpipe
    /// creates nothing, so naming an absent directory would buy a refusal
    /// naming a key file instead of a dial that simply carries no identity.
    func testWithNowhereToKeepAKeyThereIsNoDirectory() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identities = files()
        FileManager.default.createFile(
            atPath: identities.directory.path(percentEncoded: false),
            contents: Data("not a directory".utf8))

        XCTAssertNil(identities.directoryPath())
    }

    /// The directory is made, and nothing is put in it. This app writes no key
    /// file and names none: the first one appears when modelpipe writes it, on
    /// a dial that was handed this directory.
    func testNamingTheDirectoryPutsNothingInIt() throws {
        let identities = files()

        let directory = try XCTUnwrap(identities.directoryPath())

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory), [],
            "something on this side wrote into the directory modelpipe owns")
    }
}
