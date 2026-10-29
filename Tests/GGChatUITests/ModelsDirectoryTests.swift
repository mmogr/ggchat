import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// Where the models are kept: `ggchat-models` under Application Support,
/// private to this user and marked out of the backup at launch and again
/// after each finished download. Every test that makes the directory makes
/// it in a scratch directory of its own (`StoreScratch`); the one that names
/// the app's real place makes nothing there.
@MainActor
final class ModelsDirectoryTests: XCTestCase {
    private let scratch = StoreScratch()

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    private var location: ModelsDirectory {
        ModelsDirectory(directory: scratch.support.appending(path: "ggchat-models", directoryHint: .isDirectory))
    }

    private func makeModel(library: any ModelLibrary = MockLibrary()) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "ModelsDirectoryTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: MockEngine(registry: registry), library: library, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        model.onDevice.modelsDirectory = location
        return model
    }

    /// Clears the mark, as something that replaced the directory would.
    private func unmark(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try url.setResourceValues(values)
    }

    /// Made, the directory is readable by this user alone and marked out of
    /// the backup.
    func testTheDirectoryIsPrivateAndOutOfTheBackup() throws {
        try location.prepare()

        XCTAssertEqual(try scratch.isExcludedFromBackup(location.directory), true, "every model would ride the backup")
        let mode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: location.directory.path(percentEncoded: false))[
                .posixPermissions] as? NSNumber)
        XCTAssertEqual(
            mode.int16Value & 0o077, 0, "another user can read the models: \(String(mode.int16Value, radix: 8))")
    }

    /// A directory that is already there without the mark is marked at
    /// launch: the launch that made it is not the only one that sets it.
    func testTheLaunchMarksADirectoryMadeWithoutTheMark() throws {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        XCTAssertNotEqual(try scratch.isExcludedFromBackup(location.directory), true, "the directory began marked")

        makeModel().load()

        XCTAssertEqual(try scratch.isExcludedFromBackup(location.directory), true)
    }

    /// The mark is set again once a download finishes, so a directory whose
    /// mark went while the library wrote into it is marked by the end.
    func testAFinishedDownloadMarksTheDirectoryAgain() async throws {
        let sleeper = GatedSleeper()
        let library = MockLibrary(sleeper: sleeper)
        let model = makeModel(library: library)
        let offers = try await library.quantizations(
            repo: "mock/phone-1.7b-GGUF",
            reading: DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false))
        let fits = try XCTUnwrap(offers.first)
        model.download(fits, of: "mock/phone-1.7b-GGUF")
        try unmark(location.directory)
        XCTAssertEqual(try scratch.isExcludedFromBackup(location.directory), false)

        for _ in 1...10 { await sleeper.release() }
        let deadline = ContinuousClock.now + .seconds(10)
        while try scratch.isExcludedFromBackup(location.directory) != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(
            try scratch.isExcludedFromBackup(location.directory), true, "a finished download left it unmarked")
        XCTAssertEqual(model.onDevice.downloads.values.first?.state, .done)
    }

    /// The app's own place is `<Application Support>/ggchat-models`, and
    /// naming it makes nothing. Every other test names its own place, so
    /// without this one a default at the wrong place would pass them all.
    func testTheAppsOwnModelsAreUnderApplicationSupport() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let place = support.appending(path: "ggchat-models", directoryHint: .isDirectory)
        let before = scratch.exists(place)

        let own = try XCTUnwrap(ModelsDirectory.applicationSupport())

        XCTAssertEqual(ModelsDirectory.directoryName, "ggchat-models")
        XCTAssertEqual(
            own.directory.standardizedFileURL.path(percentEncoded: false),
            place.standardizedFileURL.path(percentEncoded: false))
        XCTAssertEqual(scratch.exists(place), before, "naming the app's own place made it")
    }

    /// The room for a download is the volume's figure for something the
    /// person asked for, read where the directory is.
    func testTheRoomIsTheVolumesFigureForAnImportantDownload() throws {
        try location.prepare()
        let room = try XCTUnwrap(location.room(), "the volume would not say how much room it has")
        XCTAssertGreaterThan(room, 0)
        let values = try location.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let figure = try XCTUnwrap(values.volumeAvailableCapacityForImportantUsage)
        // Read twice, a moment apart, on a volume other work is writing to.
        XCTAssertEqual(Double(room), Double(figure), accuracy: Double(1 << 30))
    }
}
