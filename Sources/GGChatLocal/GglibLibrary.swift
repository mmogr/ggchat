import Foundation
import GGChatCore
import GGLib
import Synchronization

/// gglib's own model library behind the app's `ModelLibrary`: what gglib
/// suggests for this device, Hugging Face searched through gglib, each
/// quantization of a repository judged against this device's reading, the
/// models installed, removing one, and downloads, each one's steps pulled
/// from gglib's watch.
///
/// The library is opened at the first call that asks it something, or at
/// the engine's first serve, over
/// ``LibraryFolders`` made first, with no Hugging Face token: public
/// repositories only, and one that wants a token says so
/// (`OnDeviceError.authRequired`). An open that fails is not kept, so the
/// next call tries again. Pausing and resuming open nothing: a library never
/// opened has no download to pause, so a build that neither browses nor
/// serves gglib's engine never makes its folders.
///
/// gglib's engine is served from the library this opens
/// (``GglibEngine/init(library:)``), never from one of its own: gglib stops
/// the engine served before at the next serve only within one library.
///
/// Every record and error crosses through `Mapping.swift`, so nothing above
/// this module names a binding type. The library is held as gglib's
/// `LibraryProtocol`, which uniffi generates beside the class, so a test can
/// stand a fake in for it and for a download's watch.
public final class GglibLibrary: ModelLibrary {
    /// How the library is opened: gglib's `openLibrary`, or a test's fake.
    typealias Open = @Sendable () async throws -> any LibraryProtocol

    private let open: Open
    /// The open under way or done; nil before the first call and after an
    /// open that failed.
    private let opening = Mutex<Task<any LibraryProtocol, any Error>?>(nil)

    /// The library in `folders`, opened when it is first asked something.
    public convenience init(folders: LibraryFolders) {
        self.init(open: { try await Self.open(folders) })
    }

    init(open: @escaping Open) {
        self.open = open
    }

    /// What the app says when the library's folders could not be made
    /// private and out of the backup.
    static let foldersNotKept =
        "This device could not keep a place for its model library out of its backups, so the library was not opened."

    /// Makes `folders` and opens gglib's library in them, with no token.
    static func open(_ folders: LibraryFolders) async throws -> any LibraryProtocol {
        do {
            try folders.prepare()
        } catch {
            throw OnDeviceError.internal(message: foldersNotKept)
        }
        let dirs = LibraryDirs(
            dataDir: folders.data.path(percentEncoded: false), modelsDir: folders.models.path(percentEncoded: false))
        return try await openLibrary(dirs: dirs, hfToken: nil)
    }

    /// The library, opened by the first call that needs it and by one open
    /// at a time. A failed open is forgotten, and thrown as the app says it.
    /// `GglibEngine` serves from this same handle, so the process holds one
    /// library over one `gglib.db`.
    func library() async throws -> any LibraryProtocol {
        let open = open
        let attempt = opening.withLock { held in
            if let held { return held }
            let started = Task { try await open() }
            held = started
            return started
        }
        do {
            return try await attempt.value
        } catch {
            opening.withLock { held in
                if held == attempt { held = nil }
            }
            throw OnDeviceError(thrown: error)
        }
    }

    /// The library if an open has begun, once it has landed; nil if none
    /// has, or it failed.
    private func opened() async -> (any LibraryProtocol)? {
        guard let attempt = opening.withLock({ $0 }) else { return nil }
        return try? await attempt.value
    }

    /// Asks the library `question`, opening it first, and throws what fails
    /// as the app says it.
    private func asking<Answer: Sendable>(
        _ question: (any LibraryProtocol) async throws -> Answer
    ) async throws -> Answer {
        let library = try await library()
        do {
            return try await question(library)
        } catch {
            throw OnDeviceError(thrown: error)
        }
    }

    /// gglib answers this one at once and blocks while it does, so it is
    /// asked off whatever actor called.
    @concurrent
    public func suggested(reading: GGChatCore.DeviceReading) async throws -> [GGChatCore.Suggestion] {
        try await asking { library in
            library.suggested(reading: GGLib.DeviceReading(reading)).map(GGChatCore.Suggestion.init)
        }
    }

    public func search(query: String, cursor: String?) async throws -> GGChatCore.SearchPage {
        try await asking { try await GGChatCore.SearchPage($0.search(query: query, cursor: cursor)) }
    }

    public func quantizations(
        repo: String, reading: GGChatCore.DeviceReading
    ) async throws -> [GGChatCore.QuantOffer] {
        try await asking { library in
            try await library.quantizations(repo: repo, reading: GGLib.DeviceReading(reading))
                .map(GGChatCore.QuantOffer.init)
        }
    }

    public func installed() async throws -> [GGChatCore.InstalledModel] {
        try await asking { try await $0.installed().map(GGChatCore.InstalledModel.init) }
    }

    public func remove(id: Int64) async throws {
        try await asking { try await $0.remove(id: id) }
    }

    public func download(
        repo: String, quantization: String
    ) async throws -> AsyncStream<GGChatCore.DownloadProgress> {
        let watch = try await asking { try await $0.download(repo: repo, quantization: quantization) }
        return Self.steps(of: watch)
    }

    public func pauseAll() async {
        await opened()?.pauseAll()
    }

    public func resumeAll() async {
        await opened()?.resumeAll()
    }

    /// One download's steps, pulled from gglib's watch one at a time as
    /// `ModelpipeSession` pulls a pipe's statuses: each as gglib answers it,
    /// current first, and the stream ends once gglib answers none, after done
    /// or failed. A pause is not an end: gglib's watch answers again once the
    /// download is resumed, and the steps go on in the same stream, since a
    /// stream that ended there would read to the app as a failed download.
    ///
    /// Ending the stream before then calls the download off: the watch is
    /// cancelled, which stops the download, keeping what it fetched for the
    /// next attempt, and makes the pull's waiting `next()` answer none. Swift
    /// cannot cancel a call into the library, so the watch is what ends the
    /// pull, not its task.
    static func steps(of watch: any DownloadWatchProtocol) -> AsyncStream<GGChatCore.DownloadProgress> {
        AsyncStream { continuation in
            // Set before the pull starts, so a watch that ends at once ends
            // the stream as finished, never as cancelled.
            continuation.onTermination = { ending in
                guard case .cancelled = ending else { return }
                watch.cancel()
            }
            Task {
                while let step = await watch.next() {
                    continuation.yield(GGChatCore.DownloadProgress(step))
                }
                continuation.finish()
            }
        }
    }
}
