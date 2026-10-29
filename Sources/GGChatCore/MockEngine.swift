// The whole file is DEBUG-only, for `MockPipeConnector.swift`'s reason: a
// release build carries neither the types nor their symbols, and
// `scripts/check_no_mock_in_release.sh` fails one that does. A release build
// has gglib's engine on an iPhone and `UnavailableEngine` elsewhere.
#if DEBUG
    import Foundation
    import Synchronization

    /// Stands in for gglib's engine in a DEBUG build launched with
    /// `-ggchat-mock-engine <behaviour>`, and in tests: serving binds a
    /// `MockProvider` to ``baseURL`` in the `LoopbackProviderRegistry`. The
    /// session is idle until a chat arrives, and then loads the model as
    /// gglib's engine does for the first request that names one, walking its
    /// status on a `Sleeper`, as `MockPipeConnector` walks a pipe's, before
    /// the reply streams.
    ///
    /// The provider reports a context of 4096 beside its counts, as the
    /// engine's proxy reports the context it loaded the model with, so a
    /// reply raises the context ring.
    public struct MockEngine: LocalEngine {
        /// What the mock engine does, spelled as `-ggchat-mock-engine` takes
        /// it.
        public enum Behaviour: String, Sendable, CaseIterable {
            /// Loads its one model in two steps, and answers.
            case ready
            /// Loads it in ten steps, and answers.
            case slow
            /// Fails to load it, and refuses every chat, trying again at each.
            case fails
            /// Refuses every chat as gglib refuses a model too big for the
            /// device: 507, `model_does_not_fit`, before loading anything.
            case tooBig = "too-big"
            /// Has no model to list.
            case noModels = "no-models"
        }

        /// Where the mock engine answers: one address for every session, so
        /// a session served again is found where the last one was.
        public static let baseURL = URL(string: "http://127.0.0.1:49150/v1")!
        /// The key every mock session hands back. The mock provider admits
        /// any.
        public static let apiKey = "mock-engine-key"
        /// The context the mock loads its model with, and reports.
        public static let contextSize = 4_096
        /// The one model the mock engine lists.
        public static let model = ModelInfo(
            id: "mock-phone-1.7b", ownedBy: "ggchat", description: "a canned model small enough for a phone",
            contextWindow: 40_960, capabilities: ["reasoning"])

        public var behaviour: Behaviour
        public var sleeper: any Sleeper
        public var stepDelay: Duration
        public var registry: LoopbackProviderRegistry
        /// What answers at ``baseURL``, in place of the behaviour's own mock
        /// provider, for a test that records what was sent.
        public var provider: (any Provider)?
        /// What the engine lists as its models: the catalogue a `MockLibrary`
        /// installs into, when the two are handed the same one, as gglib's
        /// proxy lists what its library installed.
        public let catalogue: MockLibrary.Catalogue

        public init(
            behaviour: Behaviour = .ready,
            sleeper: any Sleeper = ImmediateSleeper(),
            stepDelay: Duration = .milliseconds(400),
            registry: LoopbackProviderRegistry = .shared,
            provider: (any Provider)? = nil,
            catalogue: MockLibrary.Catalogue? = nil
        ) {
            self.behaviour = behaviour
            self.sleeper = sleeper
            self.stepDelay = stepDelay
            self.registry = registry
            self.provider = provider
            self.catalogue = catalogue ?? MockLibrary.Catalogue(behaviour: behaviour)
        }

        public var isAvailable: Bool { true }

        /// Binds the provider and hands back a session that is `idle` until
        /// the first chat. The behaviour decides what fits, not the reading,
        /// which the session keeps for a test to read back.
        public func serve(reading: DeviceReading) async throws -> any EngineSession {
            let session = MockEngineSession(
                reading: reading, walk: walk, sleeper: sleeper, stepDelay: stepDelay, registry: registry)
            registry.register(LoadingFirst(session: session, replying: provider ?? answering), at: Self.baseURL)
            return session
        }

        /// The behaviour's own provider: the mock's canned reply at a phone's
        /// pace, or a refusal before the first token, listing what the
        /// catalogue holds when it is asked.
        var answering: any Provider {
            let refusal: ProviderError? =
                switch behaviour {
                case .ready, .slow, .noModels: nil
                case .fails:
                    .server(
                        status: 500, code: "internal_error",
                        message: "The engine could not load \(Self.model.id): the mock was told to fail.")
                case .tooBig:
                    .server(
                        status: 507, code: "model_does_not_fit",
                        message: "The chat model needs 5.1 GB at its smallest context; this device gives a model "
                            + "3.2 GB. Use a smaller model, or a smaller quantization of this one.")
                }
            let replying = MockProvider(
                models: [], scripts: refusal == nil ? [MockProvider.sampleScript] : [.init(text: "")],
                sleeper: sleeper, tokenDelay: .milliseconds(25), failure: refusal, contextSize: Self.contextSize)
            return CatalogueListing(replying: replying, catalogue: catalogue)
        }

        /// The statuses a load walks through from `idle` or `failed`, one
        /// step apart. A model too big is refused before it loads, and with
        /// no model there is nothing to load.
        var walk: [EngineStatus] {
            let model = Self.model.id
            let ready = EngineStatus.ready(model: model, nCtx: UInt64(Self.contextSize))
            switch behaviour {
            case .ready: return [.loading(model: model, fraction: 0.5), ready]
            case .slow: return (1...10).map { .loading(model: model, fraction: Double($0) / 10) } + [ready]
            case .fails:
                return [
                    .loading(model: model, fraction: 0.5), .failed(model: model, reason: "the mock was told to fail"),
                ]
            case .tooBig, .noModels: return []
            }
        }
    }

    /// The session ``MockEngine`` hands back. DEBUG builds only, for the
    /// same reason.
    public final class MockEngineSession: EngineSession, Sendable {
        public let baseURL = MockEngine.baseURL
        public let apiKey = MockEngine.apiKey
        /// The reading the session was served with.
        public let reading: DeviceReading
        private let relay = StatusRelay<EngineStatus>(initial: .idle)
        private let walk: [EngineStatus]
        private let sleeper: any Sleeper
        private let stepDelay: Duration
        /// The load under way, while one is.
        private let walking = Mutex<Task<Void, Never>?>(nil)
        private let stopped = Mutex(false)
        private let registry: LoopbackProviderRegistry

        init(
            reading: DeviceReading, walk: [EngineStatus], sleeper: any Sleeper, stepDelay: Duration,
            registry: LoopbackProviderRegistry
        ) {
            self.reading = reading
            self.walk = walk
            self.sleeper = sleeper
            self.stepDelay = stepDelay
            self.registry = registry
        }

        /// Loads the model, as gglib's engine loads one for the first request
        /// that names it, unless it is loaded: walks the statuses, one step
        /// apart. A load under way is joined, and one that failed is walked
        /// again, as gglib tries again at the next request. Returns once the
        /// walk has ended.
        func load() async {
            let load: Task<Void, Never>? = walking.withLock { walking in
                if let walking { return walking }
                switch relay.current {
                case .idle, .failed: break
                case .loading, .ready, .stopped: return nil
                }
                guard !stopped.withLock({ $0 }) else { return nil }
                let started = Task { [self] in
                    for status in walk {
                        guard (try? await sleeper.sleep(for: stepDelay)) != nil else { break }
                        relay.send(status)
                    }
                    self.walking.withLock { $0 = nil }
                }
                walking = started
                return started
            }
            await load?.value
        }

        public var status: AsyncStream<EngineStatus> {
            relay.stream()
        }

        public var currentStatus: EngineStatus {
            relay.current
        }

        /// Stops the walk, says `stopped`, ends the stream and unbinds the
        /// provider. A second call changes nothing: the address is shared,
        /// and a later session may be bound to it by then.
        public func shutdown() async {
            let first = stopped.withLock { stopped in
                defer { stopped = true }
                return !stopped
            }
            guard first else { return }
            walking.withLock { $0?.cancel() }
            relay.send(.stopped)
            relay.finish()
            registry.unregister(baseURL)
        }
    }

    extension MockEngine {
        /// What a mock session binds: the model is loaded before each reply
        /// streams, as gglib's engine holds a request until the model it
        /// names is loaded, and the models are listed without loading any.
        /// DEBUG builds only, for the same reason, and nested so the release
        /// check finds it by the engine's name.
        fileprivate struct LoadingFirst: Provider {
            let session: MockEngineSession
            let replying: any Provider

            func models() async throws -> [ModelInfo] {
                try await replying.models()
            }

            func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
                let session = session
                let replying = replying
                return AsyncStream { continuation in
                    let task = Task {
                        await session.load()
                        for await event in replying.stream(request) { continuation.yield(event) }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        }

        /// A mock provider whose model list is a catalogue's, read at each
        /// listing. DEBUG builds only, for the same reason, and nested so the
        /// release check finds it by the engine's name.
        fileprivate struct CatalogueListing: Provider {
            let replying: MockProvider
            let catalogue: MockLibrary.Catalogue

            func models() async throws -> [ModelInfo] {
                catalogue.listed
            }

            func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
                replying.stream(request)
            }
        }
    }
#endif
