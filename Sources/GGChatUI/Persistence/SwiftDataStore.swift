import Foundation
import GGChatCore
import SwiftData

/// Owns its container: a `ModelContext` whose container has been released
/// traps on the next fetch, so the two are kept together here.
public final class SwiftDataStore: Store {
    public let container: ModelContainer
    let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    public static let schema = Schema([ProviderRecord.self, ConversationRecord.self, MessageRecord.self])

    /// The on-disk container, or an in-memory one if the disk store cannot
    /// be opened, so the app still launches and says why.
    public static func makeContainer(
        inMemory: Bool = false, log: any LogSink = OSLogSink(category: "store")
    )
        -> ModelContainer
    {
        #if DEBUG
            // `-ggchat-reset YES` starts from nothing, so a UI test sees the
            // first-run screens.
            if UserDefaults.standard.bool(forKey: "ggchat-reset") {
                deleteStoreOnDisk(log: log)
            }
        #endif
        if !inMemory {
            do {
                // iOS does not ship an Application Support directory, and
                // SwiftData will not create one, so the store fails to open
                // and everything silently lives in memory instead.
                _ = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let configuration = ModelConfiguration("ggchat", schema: schema)
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                log.log(.error, "could not open the on-disk store, falling back to memory: \(error)")
            }
        }
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData could not create even an in-memory store: \(error)")
        }
    }

    #if DEBUG
        /// Removes the store so the next launch is a first run.
        static func deleteStoreOnDisk(log: any LogSink) {
            guard
                let support = try? FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            else { return }
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: support.appending(path: "ggchat.store\(suffix)"))
            }
            log.log(.info, "store reset on request")
        }
    #endif

    // MARK: - Providers

    public func loadProviders() throws -> [ProviderConfig] {
        let records = try context.fetch(FetchDescriptor<ProviderRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        return try records.map { record in
            ProviderConfig(
                id: record.uuid, name: record.name,
                kind: try JSONDecoder().decode(ProviderConfig.Kind.self, from: record.kindData),
                defaultModel: record.defaultModel)
        }
    }

    public func save(provider: ProviderConfig) throws {
        let kindData = try JSONEncoder().encode(provider.kind)
        if let record = try fetchProvider(provider.id) {
            record.name = provider.name
            record.kindData = kindData
            record.defaultModel = provider.defaultModel
        } else {
            context.insert(
                ProviderRecord(
                    id: provider.id, name: provider.name, kindData: kindData,
                    defaultModel: provider.defaultModel, createdAt: Date()))
        }
        try context.save()
    }

    public func deleteProvider(id: UUID) throws {
        if let record = try fetchProvider(id) {
            context.delete(record)
            try context.save()
        }
    }

    private func fetchProvider(_ id: UUID) throws -> ProviderRecord? {
        try context.fetch(FetchDescriptor<ProviderRecord>()).first { $0.uuid == id }
    }

    // MARK: - Conversations

    public func loadConversations() throws -> [Conversation] {
        let records = try context.fetch(FetchDescriptor<ConversationRecord>())
        return records.map { record in
            Conversation(
                id: record.uuid, title: record.title, providerID: record.providerID, model: record.model,
                messages: record.messages.sorted { $0.order < $1.order }.map { message in
                    Message(
                        id: message.uuid, role: Role(rawValue: message.role) ?? .user, content: message.content,
                        reasoning: message.reasoning, isPartial: message.isPartial, createdAt: message.createdAt)
                },
                createdAt: record.createdAt, updatedAt: record.updatedAt)
        }
    }

    public func save(conversation: Conversation) throws {
        let record: ConversationRecord
        if let existing = try fetchConversation(conversation.id) {
            record = existing
            record.title = conversation.title
            record.providerID = conversation.providerID
            record.model = conversation.model
            record.updatedAt = conversation.updatedAt
        } else {
            record = ConversationRecord(
                id: conversation.id, title: conversation.title, providerID: conversation.providerID,
                model: conversation.model, createdAt: conversation.createdAt, updatedAt: conversation.updatedAt)
            context.insert(record)
        }
        var existing = Dictionary(record.messages.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for (order, message) in conversation.messages.enumerated() {
            if let row = existing.removeValue(forKey: message.id) {
                row.content = message.content
                row.reasoning = message.reasoning
                row.isPartial = message.isPartial
                row.order = order
            } else {
                let row = MessageRecord(
                    id: message.id, role: message.role.rawValue, content: message.content,
                    reasoning: message.reasoning, isPartial: message.isPartial, createdAt: message.createdAt,
                    order: order)
                row.conversation = record
                context.insert(row)
            }
        }
        for orphan in existing.values {
            context.delete(orphan)
        }
        try context.save()
    }

    public func deleteConversation(id: UUID) throws {
        if let record = try fetchConversation(id) {
            context.delete(record)
            try context.save()
        }
    }

    private func fetchConversation(_ id: UUID) throws -> ConversationRecord? {
        try context.fetch(FetchDescriptor<ConversationRecord>()).first { $0.uuid == id }
    }
}
