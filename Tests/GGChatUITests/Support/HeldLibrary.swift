import GGChatCore
import Synchronization

/// `MockLibrary`, answering as it does, whose pauses and resumes are kept in
/// the order they arrived and held until the test lets each one return, so a
/// test can tell which waited for which.
final class HeldLibrary: ModelLibrary {
    let inner: MockLibrary

    private struct State {
        var calls: [String] = []
        var permits = 0
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    init(inner: MockLibrary = MockLibrary()) {
        self.inner = inner
    }

    /// "pause" and "resume", in the order the calls arrived, whether or not
    /// they have returned.
    var calls: [String] {
        state.withLock { $0.calls }
    }

    /// Lets the oldest call held return, or the next to arrive return at
    /// once.
    func release() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiting.isEmpty else {
                state.permits += 1
                return nil
            }
            return state.waiting.removeFirst()
        }
        waiter?.resume()
    }

    func pauseAll() async {
        await held("pause")
        await inner.pauseAll()
    }

    func resumeAll() async {
        await held("resume")
        await inner.resumeAll()
    }

    private func held(_ call: String) async {
        await withCheckedContinuation { continuation in
            let now = state.withLock { state -> Bool in
                state.calls.append(call)
                guard state.permits > 0 else {
                    state.waiting.append(continuation)
                    return false
                }
                state.permits -= 1
                return true
            }
            if now { continuation.resume() }
        }
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
        try await inner.download(repo: repo, quantization: quantization)
    }
}
