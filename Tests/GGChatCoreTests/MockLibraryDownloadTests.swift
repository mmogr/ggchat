import Foundation
import XCTest

@testable import GGChatCore

/// The mock library's downloads, which the walks and the app's tests stand on:
/// a pause holds a walk at the bytes it had and a resume goes on from there,
/// and a finished download is installed where the mock engine sharing its
/// catalogue lists it, until it is removed.
final class MockLibraryDownloadTests: XCTestCase {
    private let phoneRepo = MockLibrary.phoneRepo

    /// Paused, a walk finishes the step it is on and says paused at those
    /// bytes; however far the clock is let run then, it goes no further.
    /// Resumed, it says running at the same bytes and walks on to done. When
    /// the pause lands, between steps or during one, is the walk's to see,
    /// so the test reads whichever step it paused after.
    func testAPauseHoldsAWalkAtItsBytesAndAResumeGoesOn() async throws {
        let sleeper = GatedSleeper()
        let library = MockLibrary(sleeper: sleeper)
        var steps = try await library.download(repo: phoneRepo, quantization: "Q4_K_M").makeAsyncIterator()
        var before: [DownloadProgress] = []
        if let queued = await steps.next() { before.append(queued) }
        await sleeper.release()
        if let first = await steps.next() { before.append(first) }
        XCTAssertEqual(before.map(\.state), [.queued, .running])

        await library.pauseAll()
        await sleeper.release()
        var paused: DownloadProgress?
        while paused == nil, let step = await steps.next() {
            if step.state == .paused { paused = step } else { before.append(step) }
        }
        let held = try XCTUnwrap(paused, "the walk never paused")
        XCTAssertEqual(held.bytes, before.last?.bytes, "the pause did not keep the bytes the walk had")
        for _ in 1...3 { await sleeper.release() }

        await library.resumeAll()
        for _ in 1...12 { await sleeper.release() }
        var rest: [DownloadProgress] = []
        while let step = await steps.next() { rest.append(step) }
        XCTAssertEqual(rest.first?.state, .running)
        XCTAssertEqual(rest.first?.bytes, held.bytes, "the clock run while paused moved the walk on")
        let bytes = (before + [held] + rest).map(\.bytes)
        XCTAssertEqual(bytes, bytes.sorted(), "the bytes went back: \(bytes)")
        XCTAssertEqual(rest.suffix(2).map(\.state), [.verifying, .done])
        XCTAssertEqual(rest.last?.bytes, MockLibrary.gigabyte)
    }

    /// A finished download is installed under the name the engine lists it
    /// by, with the offer's size and verdict, and its file is where gglib
    /// would keep it; the engine sharing the catalogue lists it, and a
    /// removal takes the row, the listing and the file away.
    func testAFinishedDownloadIsInstalledAndListedByTheEngineSharingItsCatalogue() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-mock-library-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let catalogue = MockLibrary.Catalogue(behaviour: .noModels)
        let library = MockLibrary(behaviour: .noModels, directory: folder, catalogue: catalogue)
        let engine = MockEngine(behaviour: .noModels, registry: LoopbackProviderRegistry(), catalogue: catalogue)
        let none = try await engine.answering.models()
        XCTAssertEqual(none, [])

        for await _ in try await library.download(repo: phoneRepo, quantization: "Q8_0") {}

        let name = MockLibrary.installedName(repo: phoneRepo, quantization: "Q8_0")
        XCTAssertEqual(name, "mock-phone-1.7b-Q8_0")
        let installed = try await library.installed()
        XCTAssertEqual(installed.map(\.name), [name])
        XCTAssertEqual(installed.first?.bytes, 2 * MockLibrary.gigabyte)
        XCTAssertEqual(installed.first?.verdict, .tight(ctx: 4_096))
        let listed = try await engine.answering.models()
        XCTAssertEqual(listed.map(\.id), [name])
        let finished = MockLibrary.finishedFile(name, in: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finished.path(percentEncoded: false)))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: MockLibrary.partialFile(name, in: folder).path(percentEncoded: false)))

        try await library.remove(id: try XCTUnwrap(installed.first?.id))
        let after = try await engine.answering.models()
        XCTAssertEqual(after, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path(percentEncoded: false)))
    }
}
