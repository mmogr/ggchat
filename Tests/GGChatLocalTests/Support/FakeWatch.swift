import GGLib
import Synchronization

/// A download's watch with no library behind it, answering what a test sends
/// it, a step at a time, as gglib's `DownloadWatch` answers: each call of
/// `next()` waits for the next step, `nil` ends it, and `cancel()` makes the
/// waiting call, and every later one, answer `nil`.
///
/// A subclass of the binding's class with no handle behind it, as uniffi
/// leaves room for, so `FakeLibrary.download` can hand it back; and so it
/// also has the protocol `GglibLibrary.steps(of:)` is written against. Its
/// state is all behind the mutex, which is what the restated unchecked
/// `Sendable` the binding's class carries leans on.
final class FakeWatch: DownloadWatch, @unchecked Sendable {
    private struct State {
        var sent: [GGLib.DownloadProgress?] = []
        var waiting: CheckedContinuation<GGLib.DownloadProgress?, Never>?
        var cancelled = false
    }

    private let state = Mutex(State())

    init() {
        super.init(noHandle: NoHandle())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("a fake watch has no handle")
    }

    /// Whether the watch was cancelled.
    var isCancelled: Bool { state.withLock { $0.cancelled } }

    /// Whether a call of `next()` is waiting for a step.
    var isWaiting: Bool { state.withLock { $0.waiting != nil } }

    /// What the next call of `next()` answers: a step, or nil for the end.
    func send(_ step: GGLib.DownloadProgress?) {
        let waiting = state.withLock { state in
            guard let waiting = state.waiting else {
                state.sent.append(step)
                return CheckedContinuation<GGLib.DownloadProgress?, Never>?.none
            }
            state.waiting = nil
            return waiting
        }
        waiting?.resume(returning: step)
    }

    override func cancel() {
        let waiting = state.withLock { state in
            state.cancelled = true
            defer { state.waiting = nil }
            return state.waiting
        }
        waiting?.resume(returning: nil)
    }

    override func next() async -> GGLib.DownloadProgress? {
        await withCheckedContinuation { continuation in
            let answer: GGLib.DownloadProgress?? = state.withLock { state in
                if state.cancelled { return .some(nil) }
                if !state.sent.isEmpty { return .some(state.sent.removeFirst()) }
                state.waiting = continuation
                return .none
            }
            if let answer { continuation.resume(returning: answer) }
        }
    }
}

/// A step of a download in gglib's own record.
func step(_ bytes: UInt64, _ state: GGLib.DownloadState) -> GGLib.DownloadProgress {
    GGLib.DownloadProgress(id: "owner/model-GGUF:Q4_K_M", bytes: bytes, total: 100, state: state)
}
