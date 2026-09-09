import Foundation
import Synchronization

@testable import GGChatCore

/// Counts its own shutdowns, so "the pairing pipe is hung up" is a number
/// rather than an inference from a stream that finished.
final class SpyPipeSession: PipeSession, Sendable {
    let baseURL: URL
    private let closed = Mutex(0)
    private let relay: PipeStatusRelay

    /// - Parameter reached: whether the far machine ever answers. `false` is
    ///   a pipe whose port is bound and whose peer never appears, which is
    ///   what pairing must not redeem into.
    init(baseURL: URL, reached: Bool = true) {
        self.baseURL = baseURL
        self.relay = PipeStatusRelay(initial: reached ? .direct : .idle)
    }

    /// Starts at `direct` by default, because pairing now waits for the far
    /// machine before spending the code and a session that never connects
    /// would be a pipe pairing is right to refuse.
    var status: AsyncStream<PipeStatus> {
        relay.stream()
    }

    var shutdowns: Int {
        closed.withLock { $0 }
    }

    func shutdown() async {
        closed.withLock { $0 += 1 }
    }
}
