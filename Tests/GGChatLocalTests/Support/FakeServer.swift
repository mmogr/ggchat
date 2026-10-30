import GGLib
import Synchronization

/// A served engine whose state a test moves, and whose watches answer as
/// gglib's do: where it stands first, then the latest change, and nothing
/// after `stopped`. Shutting it down moves it to `stopped`, every time.
///
/// The binding's protocols name its concrete classes (`serve` answers a
/// `Server`, `status()` an `EngineWatch`), so each fake subclasses the class
/// it stands for, made with uniffi's `init(noHandle:)`, as `FakeWatch` does
/// a download's. Only what the engine calls is overridden; anything else on
/// a fake would reach for a handle it does not have.
final class FakeServer: Server, @unchecked Sendable {
    private struct State {
        var url = "http://127.0.0.1:49170/v1"
        var key = "fake-engine-key"
        var history: [GGLib.EngineState] = [.idle]
        var shutdowns = 0
        var pulls = 0
    }

    private let state = Mutex(State())

    static func make(baseUrl: String = "http://127.0.0.1:49170/v1", key: String = "fake-engine-key") -> FakeServer {
        let server = FakeServer(noHandle: Server.NoHandle())
        server.state.withLock {
            $0.url = baseUrl
            $0.key = key
        }
        return server
    }

    /// How many times the server was shut down.
    var shutdowns: Int { state.withLock { $0.shutdowns } }

    /// How many times any of its watches was asked for a state.
    var pulls: Int { state.withLock { $0.pulls } }

    /// The engine moves to `next`; every watch answers it at its next call,
    /// unless it moves again first.
    func move(to next: GGLib.EngineState) {
        state.withLock { $0.history.append(next) }
    }

    override func apiKey() -> String { state.withLock { $0.key } }
    override func baseUrl() -> String { state.withLock { $0.url } }

    override func shutdown() async {
        state.withLock {
            $0.shutdowns += 1
            $0.history.append(.stopped)
        }
    }

    override func status() -> EngineWatch {
        FakeEngineWatch.make(on: self)
    }

    /// The states the server has been in, and a pull counted.
    fileprivate func pull() {
        state.withLock { $0.pulls += 1 }
    }

    fileprivate var history: [GGLib.EngineState] { state.withLock { $0.history } }
}

/// One watch of a `FakeServer`. Polls the server on a clock, as the tests'
/// waits do, rather than suspending on a signal: its `next()` cannot be
/// called off, as the binding's cannot.
final class FakeEngineWatch: EngineWatch, @unchecked Sendable {
    private struct State {
        var server: FakeServer?
        var seen = 0
        var ended = false
    }

    private let state = Mutex(State())

    fileprivate static func make(on server: FakeServer) -> FakeEngineWatch {
        let watch = FakeEngineWatch(noHandle: EngineWatch.NoHandle())
        watch.state.withLock { $0.server = server }
        return watch
    }

    override func next() async -> GGLib.EngineState? {
        guard let server = state.withLock({ $0.server }) else { return nil }
        server.pull()
        while true {
            if state.withLock({ $0.ended }) { return nil }
            let history = server.history
            let answer: GGLib.EngineState? = state.withLock { state in
                guard state.seen < history.count, let latest = history.last else { return nil }
                state.seen = history.count
                state.ended = latest == .stopped
                return latest
            }
            if let answer { return answer }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
