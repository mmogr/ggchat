// The whole file is DEBUG-only. `PipeConnectorFactory` already declines to
// return the mock from a release build, but declining to return a type is not
// the same as not having one: until this guard, `MockPipeConnector` and
// `MockPipeSession` were `public` symbols in the shipped binary, reachable by
// anything that could name them and legible to anyone who ran `nm` on it. A
// build that cannot dial should not carry the machinery for pretending it can.
//
// `UnavailablePipeConnector` is what a release build has instead, and it is
// compiled unconditionally.
#if DEBUG
    import Foundation
    import Synchronization

    /// Stands in for modelpipe until `modelpipe-ffi` lands. Validates the ticket
    /// shape, mints a loopback base URL bound to a `MockProvider`, and walks the
    /// status idle → relayed → direct on a `Sleeper`.
    ///
    /// DEBUG builds only. A release build has `UnavailablePipeConnector` and no
    /// mock at all.
    public struct MockPipeConnector: PipeConnector {
        public var sleeper: any Sleeper
        public var stepDelay: Duration
        public var provider: any Provider
        public var registry: LoopbackProviderRegistry

        public init(
            sleeper: any Sleeper = ImmediateSleeper(),
            stepDelay: Duration = .milliseconds(700),
            provider: any Provider = MockProvider(),
            registry: LoopbackProviderRegistry = .shared
        ) {
            self.sleeper = sleeper
            self.stepDelay = stepDelay
            self.provider = provider
            self.registry = registry
        }

        public func connect(ticket: String, token: String) async throws -> any PipeSession {
            if case .failure(let shape) = Ticket.validateShape(ticket) {
                throw PipeConnectError.invalidTicket(shape)
            }
            guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw PipeConnectError.missingToken
            }
            let baseURL = registry.register(provider)
            return MockPipeSession(baseURL: baseURL, sleeper: sleeper, stepDelay: stepDelay, registry: registry)
        }
    }

    /// The session `MockPipeConnector` hands back. DEBUG builds only, for the
    /// same reason.
    public final class MockPipeSession: PipeSession, Sendable {
        public let baseURL: URL
        private let relay = PipeStatusRelay(initial: .idle)
        private let walk = Mutex<Task<Void, Never>?>(nil)
        private let registry: LoopbackProviderRegistry

        init(baseURL: URL, sleeper: any Sleeper, stepDelay: Duration, registry: LoopbackProviderRegistry) {
            self.baseURL = baseURL
            self.registry = registry
            let relay = self.relay
            walk.withLock {
                $0 = Task {
                    for status in [PipeStatus.relayed, .direct] {
                        guard (try? await sleeper.sleep(for: stepDelay)) != nil else { return }
                        relay.send(status)
                    }
                }
            }
        }

        public var status: AsyncStream<PipeStatus> {
            relay.stream()
        }

        public var currentStatus: PipeStatus {
            relay.current
        }

        /// Simulates the other machine going away, for the reconnect UI.
        public func forceClosed() {
            walk.withLock { $0?.cancel() }
            relay.send(.closed)
        }

        public func shutdown() async {
            walk.withLock { $0?.cancel() }
            relay.send(.closed)
            relay.finish()
            registry.unregister(baseURL)
        }
    }
#endif
