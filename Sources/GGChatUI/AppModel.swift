import Foundation
import GGChatCore
import Observation

/// The app's state: providers, conversations, selection. Chat streaming
/// arrives in the next step; this is the shell.
@Observable
public final class AppModel {
    public private(set) var providers: [ProviderConfig] = []
    public private(set) var conversations: [Conversation] = []
    public var selectedConversationID: UUID?
    /// The last failure worth telling the user about, as its own sentence.
    public var lastError: String?
    /// The reply being streamed, if any.
    public internal(set) var liveReply: LiveReply?
    var streamTask: Task<Void, Never>?
    var streamErrors: [UUID: ProviderError] = [:]
    var modelsByProvider: [UUID: [ModelInfo]] = [:]
    var pipeStatuses: [UUID: PipeStatus] = [:]
    var pipeSessions: [UUID: any PipeSession] = [:]
    var statusTasks: [UUID: Task<Void, Never>] = [:]
    var connecting: Set<UUID> = []
    var proxyStatusAvailability: [UUID: Bool] = [:]
    /// Changes once each time a pipe first reaches a connected state; the
    /// one haptic in the app fires on it.
    public internal(set) var connectedPulse = 0

    public let diagnostics: Diagnostics
    let store: any Store
    let secrets: any Secrets
    let log: any LogSink
    let registry: LoopbackProviderRegistry
    let pipeConnector: any PipeConnector
    let now: () -> Date

    /// Where the in-process mock provider answers in DEBUG builds, the same
    /// address after every launch so a saved mock provider keeps working.
    public static let mockBaseURL = URL(string: "http://127.0.0.1:49151/v1")!

    public init(
        store: any Store,
        secrets: any Secrets,
        log: any LogSink = OSLogSink(category: "app"),
        registry: LoopbackProviderRegistry = .shared,
        pipeConnector: any PipeConnector = PipeConnectorFactory.make(),
        diagnostics: Diagnostics = Diagnostics(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.secrets = secrets
        self.log = log
        self.registry = registry
        self.pipeConnector = pipeConnector
        self.diagnostics = diagnostics
        self.now = now
        #if DEBUG
            registry.register(
                MockProvider(sleeper: ContinuousClockSleeper(), tokenDelay: .milliseconds(25)), at: Self.mockBaseURL)
        #endif
    }

    public var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    public func load() {
        do {
            providers = try store.loadProviders()
            conversations = try store.loadConversations().sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            report(error)
        }
    }

    // MARK: - Conversations

    @discardableResult
    public func newConversation() -> Conversation {
        let provider = providers.first
        let stamp = now()
        let conversation = Conversation(
            providerID: provider?.id, model: provider?.defaultModel, createdAt: stamp, updatedAt: stamp)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        persist(conversation)
        return conversation
    }

    public func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id { selectedConversationID = nil }
        do {
            try store.deleteConversation(id: id)
        } catch {
            report(error)
        }
    }

    public func update(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index] = conversation
        persist(conversation)
    }

    func persist(_ conversation: Conversation) {
        do {
            try store.save(conversation: conversation)
        } catch {
            report(error)
        }
    }

    // MARK: - Providers

    public func addProvider(_ config: ProviderConfig, credentials: [SecretKind: String]) {
        do {
            for (kind, value) in credentials where !value.isEmpty {
                try secrets.setSecret(value, kind, for: config.id)
            }
            try store.save(provider: config)
            providers.append(config)
        } catch {
            report(error)
        }
    }

    public func updateProvider(_ config: ProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == config.id }) else { return }
        providers[index] = config
        do {
            try store.save(provider: config)
        } catch {
            report(error)
        }
    }

    public func removeProvider(_ id: UUID) {
        providers.removeAll { $0.id == id }
        Task { await disconnectPipe(for: id) }
        do {
            try secrets.removeAll(for: id)
            try store.deleteProvider(id: id)
        } catch {
            report(error)
        }
    }

    public func provider(for conversation: Conversation) -> ProviderConfig? {
        providers.first { $0.id == conversation.providerID }
    }

    func report(_ error: any Error) {
        lastError = error.localizedDescription
        log.log(.error, "\(type(of: error)): \(error.localizedDescription)")
    }
}

extension AppModel {
    /// Seeded, in-memory, for previews.
    public static var preview: AppModel {
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            pipeConnector: MockPipeConnector(), diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "preview")!))
        model.addProvider(
            ProviderConfig(name: "Mock", kind: .openAICompatible(baseURL: mockBaseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.addProvider(
            ProviderConfig(name: "Home", kind: .pipe(ticketDigest: "0123456789abcdef")),
            credentials: [.ticket: "pipeabcdefghijklmnop", .token: "preview"])
        let conversation = model.newConversation()
        var seeded = conversation
        seeded.messages = [
            Message(role: .user, content: "What does a ticket look like?", createdAt: seeded.createdAt),
            Message(
                role: .assistant,
                content: "It starts with `pipe` and is followed by base32 with no padding.",
                createdAt: seeded.createdAt),
        ]
        model.update(seeded)
        return model
    }
}
