import Foundation
import GGChatCore
import Observation

/// The app's state: providers, conversations, selection. Chat streaming
/// arrives in the next step; this is the shell.
@Observable
public final class AppModel {
    public internal(set) var providers: [ProviderConfig] = []
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
    /// Why each pipe last closed, for as long as it is closed.
    ///
    /// Written only by `setPipeStatus`, and `scripts/check_one_status_writer.sh`
    /// holds it to that. Being shown as closed and having a reason for it are
    /// one event, in the same way that being shown as closed and being counted
    /// as a close already are — a reason written from anywhere else could
    /// describe a different close from the one on screen.
    var pipeCloseReasons: [UUID: PipeCloseReason] = [:]
    var pipeSessions: [UUID: any PipeSession] = [:]
    /// When each pipe's machine was last heard, and the pipes whose machine
    /// has failed to answer since they last connected; see
    /// `AppModel+LastHeard`.
    var lastHeardAt: [UUID: Date] = [:]
    var unanswered: Set<UUID> = []
    var statusTasks: [UUID: Task<Void, Never>] = [:]
    var connecting: Set<UUID> = []
    /// Which attempt the latest dial for each provider is. It goes up when a
    /// dial starts and again when one is called off, so a dial that returns
    /// late can tell that its session is no longer the one to install.
    var dialGeneration: [UUID: Int] = [:]
    /// The resume pass in flight, so a hang-up can call it off between dials.
    var resumeInFlight: Task<Void, Never>?
    /// The hang-up pass in flight, so a resume waits for it instead of
    /// skipping every pipe it is still taking down.
    var hangUpInFlight: Task<Void, Never>?
    /// Set on the way to the background and cleared on the way back, so a
    /// dial that lands in between hangs itself up.
    var isAway = false
    var proxyStatusAvailability: [UUID: Bool] = [:]
    /// The gglib hubs that answered a run's `PUT` as a server without runs,
    /// for as long as the app runs; see `AppModel+Runs`.
    var providersWithoutRuns: Set<UUID> = []
    /// Moved on by every new probe and by every pipe that comes up, so an
    /// answer from before either is discarded rather than kept.
    var probeGeneration: [UUID: Int] = [:]
    /// The providers a conversation has been opened on, and each one's
    /// opening still under way; see `AppModel+Opening`.
    var followed: Set<UUID> = []
    var opening: [UUID: Task<Void, Never>] = [:]
    /// The send waiting for its pipe, if one is; see `AppModel+Waiting`.
    var pipeWait: PipeWait?
    /// Changes once each time a pipe first reaches a connected state; the
    /// one haptic in the app fires on it.
    public internal(set) var connectedPulse = 0

    public let diagnostics: Diagnostics
    let store: any Store
    let secrets: any Secrets
    let log: any LogSink
    let registry: LoopbackProviderRegistry
    let pipeConnector: any PipeConnector
    /// Who reads a pairing string for the forms and the scanner. The real
    /// one in every build; see `PipeConnectorFactory.makePairingReader()`.
    ///
    /// Internal, like `pipeConnector` above it: nothing outside `GGChatUI`
    /// reads it, and the test that asserts what it is uses `@testable`.
    let pairingReader: any PairingReader
    /// What says the network under this device has changed, and the task that
    /// passes it on to the pipes; see `startWatchingTheNetwork()`.
    let networkWatcher: any NetworkPathWatching
    var networkTask: Task<Void, Never>?
    let now: () -> Date

    /// Where the in-process mock provider answers in DEBUG builds, the same
    /// address after every launch so a saved mock provider keeps working.
    public static let mockBaseURL = URL(string: "http://127.0.0.1:49151/v1")!
    /// Where the DEBUG build's refusing mock answers. Every chat request it
    /// gets is refused before its first token, with the code and the sentence
    /// modelpipe's edge wrote to a phone whose key the serving machine had
    /// forgotten, so the screen that refusal lands on can be walked to.
    public static let refusingMockBaseURL = URL(string: "http://127.0.0.1:49152/v1")!

    public init(
        store: any Store,
        secrets: any Secrets,
        log: any LogSink = OSLogSink(category: "app"),
        registry: LoopbackProviderRegistry = .shared,
        pipeConnector: any PipeConnector = PipeConnectorFactory.make(),
        pairingReader: any PairingReader = PipeConnectorFactory.makePairingReader(),
        networkWatcher: any NetworkPathWatching = NWPathNetworkWatcher(),
        diagnostics: Diagnostics = Diagnostics(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.secrets = secrets
        self.log = log
        self.registry = registry
        self.pipeConnector = pipeConnector
        self.pairingReader = pairingReader
        self.networkWatcher = networkWatcher
        self.diagnostics = diagnostics
        self.now = now
        #if DEBUG
            registry.register(
                MockProvider(sleeper: ContinuousClockSleeper(), tokenDelay: .milliseconds(25)), at: Self.mockBaseURL)
            registry.register(
                MockProvider(
                    scripts: [.init(text: "")],
                    failure: .server(status: 401, code: "invalid_api_key", message: "invalid or missing bearer token")),
                at: Self.refusingMockBaseURL)
        #endif
    }

    public var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    public func load() {
        do {
            providers = try store.loadProviders()
            lastHeardAt = try store.loadLastHeard()
            conversations = try store.loadConversations().sorted { $0.updatedAt > $1.updatedAt }
            // Reopening the app returns you to the conversation you left.
            if selectedConversationID == nil {
                selectedConversationID = conversations.first?.id
            }
        } catch {
            report(error)
        }
        startWatchingTheNetwork()
        resumeRuns()
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
        // Its reply in flight is put down as Stop puts it down. A waiting one
        // would otherwise wait on, with no Stop left on screen to end it. A
        // run the hub is writing for it away from here is stopped too.
        if liveReply?.conversationID == id { stop() }
        if let conversation = conversations.first(where: { $0.id == id }) { stopDetachedRuns(in: conversation) }
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

    func report(_ error: any Error) {
        lastError = error.localizedDescription
        log.log(.error, "\(type(of: error)): \(error.localizedDescription)")
    }
}
