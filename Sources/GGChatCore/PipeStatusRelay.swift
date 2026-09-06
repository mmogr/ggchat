import Synchronization

/// Multicasts a `PipeStatus` to any number of `AsyncStream` subscribers.
/// Every subscriber receives the current value first, then each change.
public final class PipeStatusRelay: Sendable {
    private struct State {
        var current: PipeStatus
        var subscribers: [Int: AsyncStream<PipeStatus>.Continuation] = [:]
        var nextID = 0
        var finished = false
    }

    private let state: Mutex<State>

    public init(initial: PipeStatus = .idle) {
        state = Mutex(State(current: initial))
    }

    public var current: PipeStatus {
        state.withLock { $0.current }
    }

    /// Publishes a new status. Equal consecutive values are still delivered.
    public func send(_ status: PipeStatus) {
        state.withLock { state in
            guard !state.finished else { return }
            state.current = status
            for continuation in state.subscribers.values {
                continuation.yield(status)
            }
        }
    }

    /// Ends every subscriber's stream. Later `send` calls are ignored.
    public func finish() {
        // Finishing a continuation runs its termination handler synchronously,
        // and that handler takes this lock, so finish outside it.
        let continuations: [AsyncStream<PipeStatus>.Continuation] = state.withLock { state in
            state.finished = true
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for continuation in continuations {
            continuation.finish()
        }
    }

    public func stream() -> AsyncStream<PipeStatus> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: PipeStatus.self, bufferingPolicy: .unbounded)
        let id: Int = state.withLock { state in
            let id = state.nextID
            state.nextID += 1
            continuation.yield(state.current)
            if state.finished {
                continuation.finish()
            } else {
                state.subscribers[id] = continuation
            }
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }
}
