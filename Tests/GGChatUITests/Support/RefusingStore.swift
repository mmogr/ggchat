import Foundation
import GGChatCore

@testable import GGChatUI

/// A store either half of which can be told to refuse, so what the app does
/// when a durable write will not go is not a guess.
@MainActor
final class RefusingStore: Store {
    struct Refused: Error, LocalizedError {
        var errorDescription: String? { "the store refused" }
    }

    let inner = InMemoryStore()
    var refusesSaves = false
    var refusesDeletes = false

    func loadProviders() throws -> [ProviderConfig] {
        try inner.loadProviders()
    }

    func save(provider: ProviderConfig) throws {
        if refusesSaves { throw Refused() }
        try inner.save(provider: provider)
    }

    func deleteProvider(id: UUID) throws {
        if refusesDeletes { throw Refused() }
        try inner.deleteProvider(id: id)
    }

    func loadLastHeard() throws -> [UUID: Date] {
        try inner.loadLastHeard()
    }

    func save(lastHeard: Date, forProvider id: UUID) throws {
        if refusesSaves { throw Refused() }
        try inner.save(lastHeard: lastHeard, forProvider: id)
    }

    func loadHubChats(forProvider id: UUID) throws -> SeenHubChats? {
        try inner.loadHubChats(forProvider: id)
    }

    func save(hubChats: [SeenHubChat], seenAt: Date, forProvider id: UUID) throws {
        if refusesSaves { throw Refused() }
        try inner.save(hubChats: hubChats, seenAt: seenAt, forProvider: id)
    }

    func loadHubRuns(forProvider id: UUID) throws -> [HeldHubRun] {
        try inner.loadHubRuns(forProvider: id)
    }

    func save(hubRuns: [HeldHubRun], forProvider id: UUID) throws {
        if refusesSaves { throw Refused() }
        try inner.save(hubRuns: hubRuns, forProvider: id)
    }

    func loadConversations() throws -> [Conversation] {
        try inner.loadConversations()
    }

    func save(conversation: Conversation) throws {
        try inner.save(conversation: conversation)
    }

    func deleteConversation(id: UUID) throws {
        try inner.deleteConversation(id: id)
    }
}
