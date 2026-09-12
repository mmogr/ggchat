// The whole file is DEBUG-only. `PipeConnectorFactory` already declines to
// return the mock from a release build, but declining to return a type is not
// the same as not having one: until this guard, `MockPipeConnector` and
// `MockPipeSession` were `public` symbols in the shipped binary, reachable by
// anything that could name them and legible to anyone who ran `nm` on it. A
// shipped build should not carry the machinery for pretending to dial.
//
// A release build has `ModelpipeConnector` instead. `UnavailablePipeConnector`
// is compiled unconditionally, as the sentinel the release check looks for.
#if DEBUG
    import Foundation
    import Synchronization

    /// Stands in for modelpipe in DEBUG builds. Validates the ticket shape,
    /// mints a loopback base URL bound to a `MockProvider`, and walks the
    /// status idle → relayed → direct on a `Sleeper`.
    ///
    /// DEBUG builds only. A release build has `ModelpipeConnector` and no mock
    /// at all.
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
        private let reason = Mutex<PipeCloseReason?>(nil)
        private let networkChanges = Mutex(0)

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

        public var closeReason: PipeCloseReason? {
            reason.withLock { $0 }
        }

        /// A mock binds no port of its own, so the number it reports is the
        /// one in the base URL the registry minted for it. The relay counters
        /// stay at zero: nothing here has ever touched a relay, and inventing
        /// numbers would make the Settings screen a place where readings are
        /// sometimes fiction.
        public var readings: PipeReadings {
            PipeReadings(port: UInt16(baseURL.port ?? 0))
        }

        /// Counted rather than discarded, so a test can assert that the app
        /// told its pipes the network had moved.
        public var networkChangeCount: Int {
            networkChanges.withLock { $0 }
        }

        public func notifyNetworkChange() async {
            networkChanges.withLock { $0 += 1 }
        }

        /// Simulates hanging up: what the Settings screen's "Force closed"
        /// control does.
        ///
        /// Reports `shutdown`, because that is honestly what it is — the app
        /// closed this pipe because somebody pressed a button. It is
        /// deliberately *not* `peerVanished`: this is the control the
        /// reconnect walk in `RemainingScreensUITests` drives, and a close
        /// that reads as unexpected is one anything watching for unexpected
        /// closes would be entitled to act on.
        public func forceClosed() {
            reason.withLock { $0 = .shutdown }
            walk.withLock { $0?.cancel() }
            relay.send(.closed)
        }

        /// Simulates the far machine going away without saying so — the close
        /// the binding has no case for and the one a person most wants
        /// explained.
        public func dropped() {
            reason.withLock { $0 = .peerVanished }
            walk.withLock { $0?.cancel() }
            relay.send(.closed)
        }

        public func shutdown() async {
            reason.withLock { $0 = .shutdown }
            walk.withLock { $0?.cancel() }
            relay.send(.closed)
            relay.finish()
            registry.unregister(baseURL)
        }
    }
#endif
