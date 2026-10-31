import GGChatCore
import Synchronization

/// `MockLibrary`, answering as it does, that notes at each removal whether
/// the engine still answered at its address as the library was asked, so a
/// test can tell the engine was put down before the files went, and that
/// refuses every removal when `refusing`, as gglib refuses one it cannot
/// delete.
final class WatchingLibrary: ModelLibrary {
    let inner: MockLibrary
    private let registry: LoopbackProviderRegistry
    private let refusing: Bool
    private let answered = Mutex<[Bool]>([])

    init(inner: MockLibrary, registry: LoopbackProviderRegistry, refusing: Bool = false) {
        self.inner = inner
        self.registry = registry
        self.refusing = refusing
    }

    /// For each removal asked for, in order, whether the engine answered at
    /// its address when it was.
    var engineAnsweredAtRemovals: [Bool] {
        answered.withLock { $0 }
    }

    /// The sentence a refused removal says.
    static let refusal = OnDeviceError.internal(message: "the files could not be deleted")

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
        let answering = registry.provider(for: MockEngine.baseURL) != nil
        answered.withLock { $0.append(answering) }
        if refusing { throw Self.refusal }
        try await inner.remove(id: id)
    }

    func download(repo: String, quantization: String) async throws -> AsyncStream<DownloadProgress> {
        try await inner.download(repo: repo, quantization: quantization)
    }

    func pauseAll() async {
        await inner.pauseAll()
    }

    func resumeAll() async {
        await inner.resumeAll()
    }
}
