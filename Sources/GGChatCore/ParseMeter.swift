import Synchronization

/// Counts the UTF-8 bytes of the markdown documents parsed while it is
/// bound, on any path, so a test can pin how much a streaming reply parses.
final class ParseMeter: Sendable {
    @TaskLocal static var current: ParseMeter?

    private let total = Mutex(0)

    /// The bytes parsed under this meter so far.
    var bytes: Int {
        total.withLock { $0 }
    }

    func add(_ count: Int) {
        total.withLock { $0 += count }
    }
}
