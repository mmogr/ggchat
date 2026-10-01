import GGChatCore
import Synchronization

/// The mock connector behind a switch that makes it refuse.
///
/// Until ``answer()``, every dial fails with a sentence of the binding's
/// kind, as a machine that is asleep or off the network does; from then on
/// dials and pairings are the mock's. One connector for both, so one model
/// can be walked through a refused dial, a dial that lands and a pairing.
final class SwitchedConnector: PipeConnector {
    private let inner: MockPipeConnector
    private let refusing = Mutex(true)

    init(registry: LoopbackProviderRegistry, pairings: MockPairings) {
        inner = MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry, pairings: pairings)
    }

    /// Lets every dial from here on through to the mock.
    func answer() {
        refusing.withLock { $0 = false }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        if refusing.withLock({ $0 }) {
            throw PipeConnectError.dialFailed(message: "The other machine did not answer.", retryable: true)
        }
        return try await inner.connect(ticket: ticket, token: token)
    }

    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        try await inner.pair(pairing: pairing, deviceName: deviceName)
    }
}
