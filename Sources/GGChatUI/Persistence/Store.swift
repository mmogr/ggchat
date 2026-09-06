import Foundation
import GGChatCore

/// What the app remembers between launches, minus credentials, which live
/// in `Secrets`.
public protocol Store {
    func loadProviders() throws -> [ProviderConfig]
    func save(provider: ProviderConfig) throws
    func deleteProvider(id: UUID) throws
    func loadConversations() throws -> [Conversation]
    func save(conversation: Conversation) throws
    func deleteConversation(id: UUID) throws
}

/// Previews and tests.
public final class InMemoryStore: Store {
    private var providers: [UUID: ProviderConfig] = [:]
    private var providerOrder: [UUID] = []
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
