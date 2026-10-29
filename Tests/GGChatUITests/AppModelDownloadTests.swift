import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// Downloads to this iPhone, walked on `MockLibrary`: the bar only goes up,
/// through a pause and a resume; Cancel takes the row and the partial file
/// away; a finished download joins This iPhone's models; and one there is no
/// room for is refused before the library hears of it.
@MainActor
final class AppModelDownloadTests: XCTestCase {
    private let phoneRepo = "mock/phone-1.7b-GGUF"
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: false)
    private let scratch = StoreScratch()

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    private func makeModel(
        engine: (any LocalEngine)? = nil, library: any ModelLibrary,
        registry: LoopbackProviderRegistry = LoopbackProviderRegistry()
    ) -> AppModel {
        let defaults = UserDefaults(suiteName: "AppModelDownloadTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine ?? MockEngine(registry: registry), library: library,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// The phone repository's quantization called `name`, as the library
    /// offers it.
    private func offer(_ name: String, from library: any ModelLibrary) async throws -> QuantOffer {
        let offers = try await library.quantizations(repo: phoneRepo, reading: reading)
        return try XCTUnwrap(offers.first { $0.name == name })
    }

    /// Waits until `done` holds, for `AppModelEngineTests.waitUntil`'s
    /// reason: a download is followed on a task of its own.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// Waits until the walk is waiting on `sleeper`, and answers whether it
    /// is.
    private func isHeld(_ sleeper: GatedSleeper) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while await sleeper.held == 0, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return await sleeper.held > 0
    }

    private var modelsFolder: URL { scratch.support.appending(path: "ggchat-models", directoryHint: .isDirectory) }

    /// Each step a gated walk takes, the row's bytes only go up: through the
    /// background, which pauses the download at the bytes it had and says
    /// so, and the foreground, which resumes it from there, to the whole
    /// download at done. A resume that started the download again would take
    /// the bar back to nothing.
    func testADownloadsBarOnlyGoesUpThroughAPauseAndAResume() async throws {
        let sleeper = GatedSleeper()
        let library = MockLibrary(sleeper: sleeper)
        let model = makeModel(library: library)
        let fits = try await offer("Q4_K_M", from: library)
        let choice = QuantChoice(repo: phoneRepo, quantization: fits.name)
        var bytes: [UInt64] = []
        func step(until wanted: DownloadState, _ what: String) async {
            let reached = await waitUntil { model.onDevice.downloads[choice]?.state == wanted }
            XCTAssertTrue(reached, "\(what): the row is \(String(describing: model.onDevice.downloads[choice]))")
            bytes.append(model.onDevice.downloads[choice]?.bytes ?? 0)
        }

        model.download(fits, of: phoneRepo)
        await step(until: .queued, "queued")
        for _ in 1...3 {
            let before = bytes.last
            await sleeper.release()
            _ = await waitUntil { model.onDevice.downloads[choice]?.bytes != before }
            await step(until: .running, "running")
        }

        // The walk is waiting out its fourth step, so the pause lands
        // during that step and not between two.
        let waiting = await isHeld(sleeper)
        XCTAssertTrue(waiting, "the walk never waited for its fourth step")
        await model.scene(.background).value
        await sleeper.release()
        await step(until: .paused, "the background")
        let paused = try XCTUnwrap(model.onDevice.downloads[choice])
        XCTAssertEqual(paused.bytes, fits.totalBytes / 2, "the pause did not keep the bytes it had")
        XCTAssertEqual(DownloadBar.words(for: paused), "Paused, resumes when ggchat is open")

        await model.scene(.foreground).value
        await step(until: .running, "the foreground")
        XCTAssertEqual(bytes.last, paused.bytes, "the resume did not go on from where the pause left it")
        for _ in 1...4 {
            let before = bytes.last
            await sleeper.release()
            _ = await waitUntil { model.onDevice.downloads[choice]?.bytes != before }
            bytes.append(model.onDevice.downloads[choice]?.bytes ?? 0)
        }
        await sleeper.release()
        await step(until: .verifying, "verifying")
        await sleeper.release()
        await step(until: .done, "done")

        XCTAssertEqual(bytes, bytes.sorted(), "the bar went back: \(bytes)")
        XCTAssertEqual(bytes.last, fits.totalBytes)
        XCTAssertEqual(Set(bytes).count, 9, "a step was missed: \(bytes)")
        let running = DownloadProgress(id: "", bytes: 268_435_456, total: fits.totalBytes, state: .running)
        XCTAssertEqual(DownloadBar.words(for: running), "268.4 MB of 1.07 GB")
    }

    /// Cancel takes the row away at once, and ending the download's steps
    /// makes the library delete its partial file; nothing is installed, and
    /// Download can be chosen again.
    func testCancelTakesTheRowAndThePartialAway() async throws {
        try FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
        let sleeper = GatedSleeper()
        let library = MockLibrary(sleeper: sleeper, directory: modelsFolder)
        let model = makeModel(library: library)
        let fits = try await offer("Q4_K_M", from: library)
        let choice = QuantChoice(repo: phoneRepo, quantization: fits.name)
        let name = MockLibrary.installedName(repo: phoneRepo, quantization: fits.name)
        let partial = MockLibrary.partialFile(name, in: modelsFolder)

        model.download(fits, of: phoneRepo)
        await sleeper.release()
        await sleeper.release()
        let running = await waitUntil { model.onDevice.downloads[choice]?.bytes == fits.totalBytes / 4 }
        XCTAssertTrue(running, "the download never got going: \(String(describing: model.onDevice.downloads[choice]))")
        XCTAssertTrue(scratch.exists(partial), "the download kept no partial file")

        model.cancelDownload(choice)
        XCTAssertNil(model.onDevice.downloads[choice], "Cancel left the row")
        let deleted = await waitUntil { !scratch.exists(partial) }
        XCTAssertTrue(deleted, "the partial file outlived Cancel")
        for _ in 1...50 { await Task.yield() }
        XCTAssertNil(model.onDevice.downloads[choice], "a step sent before Cancel put the row back")
        XCTAssertFalse(scratch.exists(MockLibrary.finishedFile(name, in: modelsFolder)))
        let installed = try await library.installed().map(\.name)
        XCTAssertFalse(installed.contains(name), "a cancelled download was installed")

        model.download(fits, of: phoneRepo)
        XCTAssertEqual(model.onDevice.downloads[choice]?.state, .queued, "Download was not offered again")
        model.cancelDownload(choice)
    }

    /// A download that finishes while This iPhone's engine is serving joins
    /// the model list a conversation picks from, and becomes the provider's
    /// default as the first model listed. One that finishes before the
    /// engine serves raises nothing and is listed once a conversation opens.
    func testAFinishedDownloadJoinsThisIPhonesModels() async throws {
        let name = MockLibrary.installedName(repo: phoneRepo, quantization: "Q4_K_M")
        for serveFirst in [true, false] {
            let registry = LoopbackProviderRegistry()
            let catalogue = MockLibrary.Catalogue(behaviour: .noModels)
            let library = MockLibrary(behaviour: .noModels, catalogue: catalogue)
            let model = makeModel(
                engine: MockEngine(behaviour: .noModels, registry: registry, catalogue: catalogue), library: library,
                registry: registry)
            let config = try model.addThisIPhone(defaultModel: nil)
            model.newConversation()
            if serveFirst { await model.open(config).value }
            XCTAssertEqual(model.chatModels(for: config.id), [])

            let fits = try await offer("Q4_K_M", from: library)
            model.download(fits, of: phoneRepo)
            let installed = await waitUntil { model.onDevice.installed?.map(\.name) == [name] }
            XCTAssertTrue(installed, "the finished download is not listed as installed")
            if !serveFirst {
                XCTAssertNil(model.lastError, "a download finished before the engine served raised an alert")
                await model.open(config).value
            }
            let joined = await waitUntil { model.chatModels(for: config.id).map(\.id) == [name] }
            XCTAssertTrue(joined, "serving first \(serveFirst): the list is \(model.chatModels(for: config.id))")
            XCTAssertEqual(model.providers.first?.defaultModel, name)
        }
    }

    /// A download larger than the room the volume has is refused under its
    /// row before the library hears of it, and This iPhone is not added for
    /// it; one that fits the room exactly goes ahead. A models directory
    /// that cannot be made refuses every download, so none is written where
    /// a backup reaches.
    func testADownloadThereIsNoRoomForIsRefused() async throws {
        let library = RecordingLibrary()
        let model = makeModel(library: library)
        model.onDevice.modelsDirectory = ModelsDirectory(directory: modelsFolder) { _ in 512 << 20 }
        let fits = try await offer("Q4_K_M", from: library)
        let choice = QuantChoice(repo: phoneRepo, quantization: fits.name)

        model.download(fits, of: phoneRepo)
        XCTAssertTrue(library.downloadsAsked.isEmpty, "a download there was no room for reached the library")
        XCTAssertTrue(model.providers.isEmpty, "This iPhone was added for a download there was no room for")
        guard case .failed(let reason)? = model.onDevice.downloads[choice]?.state else {
            return XCTFail("the refusal was not said under the row")
        }
        XCTAssertEqual(
            reason, "There is no room for Q4_K_M on this iPhone: it takes 1.07 GB and 536.9 MB is free.")

        let small = try await offer("IQ2_XS", from: library)
        XCTAssertEqual(small.totalBytes, 512 << 20)
        model.download(small, of: phoneRepo)
        let asked = await waitUntil { library.downloadsAsked == ["\(phoneRepo):IQ2_XS"] }
        XCTAssertTrue(asked, "a download that fits the room was refused: \(library.downloadsAsked)")

        let blocked = makeModel(library: library)
        let notAFolder = scratch.support.appending(path: "not-a-folder")
        FileManager.default.createFile(atPath: notAFolder.path(percentEncoded: false), contents: Data("x".utf8))
        blocked.onDevice.modelsDirectory = ModelsDirectory(directory: notAFolder)
        blocked.download(fits, of: phoneRepo)
        XCTAssertEqual(blocked.onDevice.downloads[choice]?.state, .failed(reason: AppModel.directoryNotKept))
        XCTAssertEqual(library.downloadsAsked.count, 1, "a download went ahead with no directory kept out of backups")
    }
}
