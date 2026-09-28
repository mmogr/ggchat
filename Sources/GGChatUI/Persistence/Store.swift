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
    func loadConversations() throws -> [Conversation]
    func save(conversation: Conversation) throws
    func deleteConversation(id: UUID) throws
}

/// Previews and tests.
public final class InMemoryStore: Store {
    private var providers: [UUID: ProviderConfig] = [:]
    private var providerOrder: [UUID] = []
    private var lastHeard: [UUID: Date] = [:]
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
    }

    public func loadLastHeard() throws -> [UUID: Date] {
        lastHeard
    }

    public func save(lastHeard: Date, forProvider id: UUID) throws {
        guard providers[id] != nil else { return }
        self.lastHeard[id] = lastHeard
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
