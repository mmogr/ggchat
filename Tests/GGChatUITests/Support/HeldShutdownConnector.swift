import Foundation
import GGChatCore
import Synchronization

/// A connector whose sessions take as long to hang up as a test says.
///
/// `MockPipeSession.shutdown()` returns at once, so nothing built on the mock
/// can hold open the window a real hang-up has: the seconds between a
/// session's `shutdown()` being awaited and its removal from the model, in
/// which a resume used to arrive and skip the provider as "still installed".
/// Every session this produces suspends in `shutdown()` until ``release()``,
/// and counts the shutdowns that have started so a test can wait for the
/// window to open before acting inside it.
final class HeldShutdownConnector: PipeConnector {
    private let inner: MockPipeConnector
    private let released = Mutex(false)
    private let started = Mutex(0)

    init(registry: LoopbackProviderRegistry) {
        inner = MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry)
    }

    /// How many sessions have begun hanging up, released or not.
    var shutdownsStarted: Int {
        started.withLock { $0 }
    }

    /// Lets every hang-up through: the ones waiting and the ones still to come.
    func release() {
        released.withLock { $0 = true }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        HeldSession(inner: try await inner.connect(ticket: ticket, token: token), connector: self)
    }

    /// Hangs up like the mock's, and is held like every other session here:
    /// what this connector exists for is the window a slow hang-up opens.
    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        let paired = try await inner.pair(pairing: pairing, deviceName: deviceName)
        guard let session = paired.session else { return paired }
        return PairedPipe(
            session: HeldSession(inner: session, connector: self), token: paired.token,
            device: paired.device)
    }

    fileprivate func shutdownStarted() {
        started.withLock { $0 += 1 }
    }

    fileprivate var isReleased: Bool {
        released.withLock { $0 }
    }
}

/// The session behind ``HeldShutdownConnector``: everything forwards to the
/// mock except `shutdown()`, which waits to be let through.
private final class HeldSession: PipeSession, Sendable {
    private let inner: any PipeSession
    private let connector: HeldShutdownConnector

    init(inner: any PipeSession, connector: HeldShutdownConnector) {
        self.inner = inner
        self.connector = connector
    }

    var baseURL: URL { inner.baseURL }
    var status: AsyncStream<PipeStatus> { inner.status }
    var closeReason: PipeCloseReason? { inner.closeReason }
    var readings: PipeReadings { inner.readings }

    func notifyNetworkChange() async {
        await inner.notifyNetworkChange()
    }

    func shutdown() async {
        connector.shutdownStarted()
        while !connector.isReleased { await Task.yield() }
        await inner.shutdown()
    }
}
