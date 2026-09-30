import Foundation
import GGChatCore

/// What the app remembers between launches, minus credentials, which live
/// in `Secrets`.
public protocol Store {
    func loadProviders() throws -> [ProviderConfig]
    func save(provider: ProviderConfig) throws
    func deleteProvider(id: UUID) throws
    /// When each provider's machine was last heard, for the providers that
    /// have been.
    func loadLastHeard() throws -> [UUID: Date]
    /// Keeps when a provider's machine was last heard, beside its row. A
    /// provider with no row keeps nothing, and deleting the row forgets it.
    func save(lastHeard: Date, forProvider id: UUID) throws
    /// The titles of a paired Mac's chats as the list last saw them, and
    /// when, or nil if it never has. No text of a chat is ever kept.
    func loadHubChats(forProvider id: UUID) throws -> SeenHubChats?
    /// Keeps the titles a list just read, beside the provider's row, over the
    /// ones before. A provider with no row keeps nothing, and deleting the
    /// row forgets them.
    func save(hubChats: [SeenHubChat], seenAt: Date, forProvider id: UUID) throws
    /// The runs in which a paired Mac is writing replies this device sent
    /// for, so a relaunch can read them on. Never a reply's text.
    func loadHubRuns(forProvider id: UUID) throws -> [HeldHubRun]
    /// Keeps them beside the provider's row, over the ones before. A provider
    /// with no row keeps nothing, and deleting the row forgets them.
    func save(hubRuns: [HeldHubRun], forProvider id: UUID) throws
    func loadConversations() throws -> [Conversation]
    func save(conversation: Conversation) throws
    func deleteConversation(id: UUID) throws
}

/// One of a paired Mac's chats as the list last saw it: its id, its title
/// and when the Mac last changed it. Nothing else of it is kept here.
public struct SeenHubChat: Codable, Sendable, Equatable {
    public let id: Int64
    public let title: String
    public let updatedAt: String

    public init(id: Int64, title: String, updatedAt: String) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

/// A run in which a paired Mac is writing a reply to one of its chats that
/// this device sent the turn for: which run, and which chat.
public struct HeldHubRun: Codable, Sendable, Equatable {
    public let runID: String
    public let chatID: Int64

    public init(runID: String, chatID: Int64) {
        self.runID = runID
        self.chatID = chatID
    }
}

/// The titles a paired Mac's list last showed, and when it was read.
public struct SeenHubChats: Sendable, Equatable {
    public let chats: [SeenHubChat]
    public let seenAt: Date

    public init(chats: [SeenHubChat], seenAt: Date) {
        self.chats = chats
        self.seenAt = seenAt
    }
}

/// Previews and tests.
public final class InMemoryStore: Store {
    private var providers: [UUID: ProviderConfig] = [:]
    private var providerOrder: [UUID] = []
    private var lastHeard: [UUID: Date] = [:]
    private var hubChats: [UUID: SeenHubChats] = [:]
    private var hubRuns: [UUID: [HeldHubRun]] = [:]
    private var conversations: [UUID: Conversation] = [:]

    public init() {}

    public func loadProviders() throws -> [ProviderConfig] {
        providerOrder.compactMap { providers[$0] }
    }

    public func save(provider: ProviderConfig) throws {
        if providers[provider.id] == nil { providerOrder.append(provider.id) }
        providers[provider.id] = provider
    }

    public func deleteProvider(id: UUID) throws {
        providers[id] = nil
        providerOrder.removeAll { $0 == id }
        lastHeard[id] = nil
        hubChats[id] = nil
        hubRuns[id] = nil
    }

    public func loadLastHeard() throws -> [UUID: Date] {
        lastHeard
    }

    public func save(lastHeard: Date, forProvider id: UUID) throws {
        guard providers[id] != nil else { return }
        self.lastHeard[id] = lastHeard
    }

    public func loadHubChats(forProvider id: UUID) throws -> SeenHubChats? {
        hubChats[id]
    }

    public func save(hubChats: [SeenHubChat], seenAt: Date, forProvider id: UUID) throws {
        guard providers[id] != nil else { return }
        self.hubChats[id] = SeenHubChats(chats: hubChats, seenAt: seenAt)
    }

    public func loadHubRuns(forProvider id: UUID) throws -> [HeldHubRun] {
        hubRuns[id] ?? []
    }

    public func save(hubRuns: [HeldHubRun], forProvider id: UUID) throws {
        guard providers[id] != nil else { return }
        self.hubRuns[id] = hubRuns
    }

    public func loadConversations() throws -> [Conversation] {
        Array(conversations.values)
    }

    public func save(conversation: Conversation) throws {
        conversations[conversation.id] = conversation
    }

    public func deleteConversation(id: UUID) throws {
        conversations[id] = nil
    }
}
