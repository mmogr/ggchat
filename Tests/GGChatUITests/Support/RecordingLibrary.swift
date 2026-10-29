import GGChatCore
import Synchronization

/// `MockLibrary`, answering as it does, that also keeps every download it
/// was asked for, so a test can tell one never reached the library from one
/// that did.
final class RecordingLibrary: ModelLibrary {
    let inner: MockLibrary
    /// Whether each download's steps end at running, short of done or
    /// failed, as a library breaking `download`'s contract would end them.
    private let endsShort: Bool
    private let asked = Mutex<[String]>([])

    init(inner: MockLibrary = MockLibrary(), endsShort: Bool = false) {
        self.inner = inner
        self.endsShort = endsShort
    }

    /// Each download asked for, as `repo:quantization`, in order.
    var downloadsAsked: [String] {
        asked.withLock { $0 }
    }

    func suggested(reading: DeviceReading) async throws -> [Suggestion] {
        try await inner.suggested(reading: reading)
    }

    func search(query: String, cursor: String?) async throws -> SearchPage {
        try await inner.search(query: query, cursor: cursor)
    }

    func quantizations(repo: String, reading: DeviceReading) async throws -> [QuantOffer] {
        try await inner.quantizations(repo: repo, reading: reading)
    }

    func installed() async throws -> [InstalledModel] {
        try await inner.installed()
    }

    func remove(id: Int64) async throws {
        try await inner.remove(id: id)
    }

    func download(repo: String, quantization: String) async throws -> AsyncStream<DownloadProgress> {
        asked.withLock { $0.append("\(repo):\(quantization)") }
        guard endsShort else { return try await inner.download(repo: repo, quantization: quantization) }
        let id = "\(repo):\(quantization)"
        return AsyncStream { steps in
            steps.yield(DownloadProgress(id: id, bytes: 0, total: nil, state: .queued))
            steps.yield(DownloadProgress(id: id, bytes: 1, total: nil, state: .running))
            steps.finish()
        }
    }

    func pauseAll() async {
        await inner.pauseAll()
    }

    func resumeAll() async {
        await inner.resumeAll()
    }
}
