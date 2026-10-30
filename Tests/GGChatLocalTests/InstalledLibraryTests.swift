import Foundation
import GGChatCore
import XCTest

@testable import GGChatLocal

/// gglib's own library, through the Mac's slice of the framework, in folders
/// of a test's own: the folders it is opened in, and a model in it listed
/// and removed, files and row. Nothing here asks the network.
final class InstalledLibraryTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory
        .appending(path: "ggchat-library-\(UUID().uuidString)").resolvingSymlinksInPath()
    private var folders: LibraryFolders {
        LibraryFolders(
            data: root.appending(path: LibraryFolders.dataDirectoryName), models: root.appending(path: "ggchat-models"))
    }

    private var dataRoot: GglibDataRoot?

    override func setUp() {
        // gglib resolves a data root of its own for what the library does not
        // name, as a download's accelerator would; never the user's gglib.
        dataRoot = GglibDataRoot(under: root)
    }

    override func tearDownWithError() throws {
        dataRoot?.restore()
        try? FileManager.default.removeItem(at: root)
    }

    /// The database's folder is this user's alone and out of the backup, as
    /// the models' is, and gglib's database is made in it.
    func testTheLibraryIsOpenedInPrivateFoldersOutOfTheBackup() async throws {
        let installed = try await GglibLibrary(folders: folders).installed()

        XCTAssertEqual(installed, [])
        for folder in [folders.data, folders.models] {
            let mode =
                try FileManager.default.attributesOfItem(atPath: folder.path(percentEncoded: false))[.posixPermissions]
                as? Int
            XCTAssertEqual(mode, 0o700, folder.lastPathComponent)
            var url = folder
            url.removeAllCachedResourceValues()
            XCTAssertEqual(
                try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true,
                folder.lastPathComponent)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folders.data.appending(path: "gglib.db").path(percentEncoded: false))
        )
    }

    /// The app's own place for the database is `ggchat-gglib` under
    /// Application Support, beside the models wherever the app keeps them.
    func testTheAppsOwnLibraryIsUnderApplicationSupport() throws {
        let models = root.appending(path: "ggchat-models")
        let own = try XCTUnwrap(LibraryFolders.applicationSupport(models: models))

        XCTAssertEqual(own.data.lastPathComponent, "ggchat-gglib")
        XCTAssertEqual(own.data.deletingLastPathComponent().lastPathComponent, "Application Support")
        XCTAssertEqual(own.models, models)
    }

    /// A model in the library is listed with its size and its trained
    /// context; with no reading handed over it cannot be judged for want of
    /// a budget, and once one is, it is. Removing it takes its file, the
    /// folder that held only it, and its row; removing it again finds none.
    func testAModelIsListedJudgedAndRemovedWithItsFiles() async throws {
        let library = GglibLibrary(folders: folders)
        _ = try await library.installed()
        let folder = folders.models.appending(path: "test-owner/Test-GGUF")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let weights = folder.appending(path: "test-model-Q4_K_M.gguf")
        let header = syntheticGGUF()
        try header.write(to: weights)
        let id = try storeModel(at: weights, in: folders.data.appending(path: "gglib.db"))

        let listed = try await library.installed()
        XCTAssertEqual(
            listed,
            [
                InstalledModel(
                    id: id, name: "Test model", bytes: UInt64(header.count), trainedCtx: 40_960, capabilities: [],
                    verdict: .unknown(missing: .budget, cutOff: false))
            ])

        _ = try await library.suggested(
            reading: DeviceReading(physicalBytes: 8 << 30, availableBytes: 6 << 30, isSimulator: false))
        let judged = try await library.installed()
        guard case .fits = judged.first?.verdict else {
            return XCTFail("a few hundred bytes of weights did not fit 6 GB: \(judged)")
        }

        try await library.remove(id: id)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: weights.path(percentEncoded: false)),
            "the weights outlived the removal")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)), "the emptied folder was left")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folders.models.path(percentEncoded: false)),
            "the models folder went too")
        let afterwards = try await library.installed()
        XCTAssertEqual(afterwards, [])
        do {
            try await library.remove(id: id)
            XCTFail("a model already removed was removed again")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .notFound)
        }
    }
}
