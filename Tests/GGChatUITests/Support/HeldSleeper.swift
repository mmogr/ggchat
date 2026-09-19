import GGChatCore
import Synchronization

/// Holds the mock pipe's walk at `idle` until it is let go: the session is
/// installed and the far machine has not answered yet.
final class HeldSleeper: Sleeper {
    private let held = Mutex(true)

    func release() { held.withLock { $0 = false } }

    func sleep(for duration: Duration) async throws {
        while held.withLock({ $0 }) {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}
