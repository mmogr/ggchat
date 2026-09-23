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

    /// The directory this app keeps keys in is named `pipe-identities` under
    /// Application Support, and that name is as load-bearing as the name of
    /// the files inside it: change it and every paired device looks in an
    /// empty directory, mints a fresh endpoint and introduces itself to its
    /// desktop as a stranger — the same silent orphaning `BindingTests` pins
    /// the file's name against, and with no build failure either.
    ///
    /// Spelt out rather than read from the source. This is the one test that
    /// calls `applicationSupport()`, and it is safe to: the call creates the
    /// platform's own Application Support directory and appends the name
    /// without creating anything under it, so no key of this machine's real
    /// app is touched. The second assertion is that safety, and it has to
    /// sample the directory *before* `applicationSupport()` is ever called —
    /// building the path by hand to do it. Sampling afterwards reads the
    /// state the call left behind, so a version that created the directory
    /// would compare `true` against `true` and pass.
    ///
    /// Its one honest limit: on a host that already holds a real
    /// `pipe-identities`, `before` is `true` and a creating version passes
    /// here too. It detects on the hosts where the damage would be done.
    func testTheKeysLiveInADirectoryWhoseNameDoesNotMove() throws {
        let support = try XCTUnwrap(
            try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: true))
        let path = support.appending(path: "pipe-identities").path(percentEncoded: false)
        let before = FileManager.default.fileExists(atPath: path)

        let identities = try XCTUnwrap(PipeIdentityFiles.applicationSupport())

        XCTAssertEqual(identities.directory.lastPathComponent, "pipe-identities")
        XCTAssertEqual(
            FileManager.default.fileExists(atPath: path), before,
            "naming the app's own directory created it, and this test would be writing into it")
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
