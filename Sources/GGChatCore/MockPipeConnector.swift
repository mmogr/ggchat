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

    /// Stands in for modelpipe in DEBUG builds: mints a loopback base URL
    /// bound to a `MockProvider` and walks the status idle → relayed →
    /// direct on a `Sleeper`.
    ///
    /// **This mock does not read tickets.** modelpipe does, behind
    /// `ModelpipeConnector`, and this target cannot call the binding — which
    /// is the whole reason `PairingReader` is a seam of its own. So a ticket
    /// is refused here only for being blank, and anything else is accepted:
    /// a rule invented here would be a third opinion about a format neither
    /// this app nor this module owns, and the screens walked in DEBUG would
    /// be walked against it rather than against modelpipe's.
    ///
    /// DEBUG builds only. A release build has `ModelpipeConnector` and no mock
    /// at all.
    public struct MockPipeConnector: PipeConnector {
        public var sleeper: any Sleeper
        public var stepDelay: Duration
        public var provider: any Provider
        public var registry: LoopbackProviderRegistry
        /// What a pairing does here, and what it was asked. A class rather
        /// than a stored `Result` so a test can read back the device names
        /// after handing the connector to something that copied it.
        public var pairings: MockPairings

        public init(
            sleeper: any Sleeper = ImmediateSleeper(),
            stepDelay: Duration = .milliseconds(700),
            provider: any Provider = MockProvider(),
            registry: LoopbackProviderRegistry = .shared,
            pairings: MockPairings = MockPairings()
        ) {
            self.sleeper = sleeper
            self.stepDelay = stepDelay
            self.provider = provider
            self.registry = registry
            self.pairings = pairings
        }

        public func connect(ticket: String, token: String) async throws -> any PipeSession {
            guard !PairingField.isBlank(ticket) else {
                throw PipeConnectError.invalidTicket(message: "The ticket is empty.")
            }
            guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw PipeConnectError.missingToken
            }
            return makeSession()
        }

        /// Pairs the way the real connector does, minus the machine: the
        /// scripted outcome decides, and a success hands back a session on a
        /// pipe that was never hung up — which is the whole of what
        /// ``PairedPipe`` promises.
        public func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
            let token = try pairings.redeeming(for: deviceName)
            return PairedPipe(
                session: makeSession(), token: token,
                device: MockPairings.device(named: deviceName))
        }

        private func makeSession() -> MockPipeSession {
            let baseURL = registry.register(provider)
            return MockPipeSession(baseURL: baseURL, sleeper: sleeper, stepDelay: stepDelay, registry: registry)
        }
    }

    /// The answer ``MockPipeConnector/pair(pairing:deviceName:)`` gives, and
    /// the device names it was handed.
    ///
    /// The default succeeds, because the DEBUG app is where the screens are
    /// walked and a build that could never pair would leave the paired
    /// provider's own screens unreachable. A test that wants the refusal
    /// scripts one.
    public final class MockPairings: Sendable {
        private let outcome: Result<String, PipeConnectError>
        private let names = Mutex<[String?]>([])

        public init(outcome: Result<String, PipeConnectError> = .success("mock-device-key")) {
            self.outcome = outcome
        }

        /// Every device name a pairing was handed, in order — `nil` and the
        /// empty string included, because passing the provider's name in
        /// place of a missing one is the mistake worth catching.
        public var deviceNames: [String?] {
            names.withLock { $0 }
        }

        /// What the far machine would list this device as: the name it was
        /// given, or its own word for a device that sent none.
        public static func device(named deviceName: String?) -> String {
            guard let trimmed = deviceName?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
                return "this device"
            }
            return trimmed
        }

        fileprivate func redeeming(for deviceName: String?) throws -> String {
            names.withLock { $0.append(deviceName) }
            return try outcome.get()
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
