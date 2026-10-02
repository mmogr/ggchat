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

    /// A container that keeps nothing on disk: what tests open, and what the
    /// app runs from for a launch in which its store cannot be kept in
    /// `ggchat-store`. The on-disk store is opened by `open(log:)`, in
    /// `StoreDirectory.swift`.
    public static func inMemoryContainer() -> ModelContainer {
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData could not create even an in-memory store: \(error)")
        }
    }

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

    public func loadLastHeard() throws -> [UUID: Date] {
        let records = try context.fetch(FetchDescriptor<ProviderRecord>())
        var heard: [UUID: Date] = [:]
        for record in records {
            if let lastHeard = record.lastHeard { heard[record.uuid] = lastHeard }
        }
        return heard
    }

    public func save(lastHeard: Date, forProvider id: UUID) throws {
        guard let record = try fetchProvider(id) else { return }
        record.lastHeard = lastHeard
        try context.save()
    }

    /// Titles that no longer decode read as none: they are only a hint of
    /// what the Mac holds, and the next list writes them again.
    public func loadHubChats(forProvider id: UUID) throws -> SeenHubChats? {
        guard let record = try fetchProvider(id), let data = record.hubChatsData, let seenAt = record.hubSeenAt
        else { return nil }
        let chats = (try? JSONDecoder().decode([SeenHubChat].self, from: data)) ?? []
        return SeenHubChats(chats: chats, seenAt: seenAt)
    }

    public func save(hubChats: [SeenHubChat], seenAt: Date, forProvider id: UUID) throws {
        guard let record = try fetchProvider(id) else { return }
        record.hubChatsData = try JSONEncoder().encode(hubChats)
        record.hubSeenAt = seenAt
        try context.save()
    }

    /// Runs that no longer decode read as none: the Mac still writes them,
    /// and its list says so.
    public func loadHubRuns(forProvider id: UUID) throws -> [HeldHubRun] {
        guard let data = try fetchProvider(id)?.hubLiveRunsData else { return [] }
        return (try? JSONDecoder().decode([HeldHubRun].self, from: data)) ?? []
    }

    public func save(hubRuns: [HeldHubRun], forProvider id: UUID) throws {
        guard let record = try fetchProvider(id) else { return }
        record.hubLiveRunsData = hubRuns.isEmpty ? nil : try JSONEncoder().encode(hubRuns)
        try context.save()
    }

    private func fetchProvider(_ id: UUID) throws -> ProviderRecord? {
        var descriptor = FetchDescriptor<ProviderRecord>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
                        reasoning: message.reasoning, isPartial: message.isPartial,
                        failure: Self.failure(from: message.failureData), createdAt: message.createdAt,
                        runID: message.runID, runCursor: message.runCursor.flatMap(UInt32.init(exactly:)))
                },
                systemPrompt: record.systemPrompt, createdAt: record.createdAt, updatedAt: record.updatedAt,
                hasUnreadReply: record.hasUnreadReply ?? false)
        }
    }

    public func save(conversation: Conversation) throws {
        try write(conversation)
        try context.save()
    }

    /// Brings one conversation's rows in line with it, without saving them.
    ///
    /// A field is assigned only when it differs from the row's, because a
    /// `@Model` setter marks its row changed even for the value it already
    /// holds: every save used to mark every row of its conversation changed,
    /// twice a turn, though only one or two had changed (#139). A failure is
    /// encoded only when it is not the one the row already holds. Apart from
    /// `save(conversation:)` so a test can look at what a write marked before
    /// it is saved.
    func write(_ conversation: Conversation) throws {
        let record: ConversationRecord
        if let existing = try fetchConversation(conversation.id) {
            record = existing
            Self.assign(\.title, of: record, to: conversation.title)
            Self.assign(\.providerID, of: record, to: conversation.providerID)
            Self.assign(\.model, of: record, to: conversation.model)
            Self.assign(\.systemPrompt, of: record, to: conversation.systemPrompt)
            Self.assign(\.hasUnreadReply, of: record, to: conversation.hasUnreadReply)
            Self.assign(\.updatedAt, of: record, to: conversation.updatedAt)
        } else {
            record = ConversationRecord(
                id: conversation.id, title: conversation.title, providerID: conversation.providerID,
                model: conversation.model, createdAt: conversation.createdAt, updatedAt: conversation.updatedAt,
                systemPrompt: conversation.systemPrompt, hasUnreadReply: conversation.hasUnreadReply)
            context.insert(record)
        }
        var existing = Dictionary(record.messages.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for (order, message) in conversation.messages.enumerated() {
            if let row = existing.removeValue(forKey: message.id) {
                Self.assign(\.content, of: row, to: message.content)
                Self.assign(\.reasoning, of: row, to: message.reasoning)
                Self.assign(\.isPartial, of: row, to: message.isPartial)
                if Self.failure(message.failure, differsFrom: row.failureData) {
                    row.failureData = try message.failure.map { try JSONEncoder().encode($0) }
                }
                Self.assign(\.runID, of: row, to: message.runID)
                Self.assign(\.runCursor, of: row, to: message.runCursor.map(Int.init))
                Self.assign(\.order, of: row, to: order)
            } else {
                let row = MessageRecord(
                    id: message.id, role: message.role.rawValue, content: message.content,
                    reasoning: message.reasoning, isPartial: message.isPartial, createdAt: message.createdAt,
                    order: order, failureData: try message.failure.map { try JSONEncoder().encode($0) },
                    runID: message.runID, runCursor: message.runCursor.map(Int.init))
                row.conversation = record
                context.insert(row)
            }
        }
        for orphan in existing.values {
            context.delete(orphan)
        }
    }

    public func deleteConversation(id: UUID) throws {
        if let record = try fetchConversation(id) {
            context.delete(record)
            try context.save()
        }
    }

    /// A failure this build cannot read costs the failure and not the
    /// conversation, so it is `try?`: the transcript is what matters.
    private static func failure(from data: Data?) -> Failure? {
        data.flatMap { try? JSONDecoder().decode(Failure.self, from: $0) }
    }

    /// Whether a message's failure is not the one its row holds. Compared as
    /// values, so the same failure written in other bytes is the same. Bytes
    /// this build cannot read differ from no failure, so they are cleared as
    /// before.
    private static func failure(_ failure: Failure?, differsFrom data: Data?) -> Bool {
        guard let failure else { return data != nil }
        return Self.failure(from: data) != failure
    }

    /// Sets a row's field only when the value is not already there.
    private static func assign<Row, Value: Equatable>(
        _ field: ReferenceWritableKeyPath<Row, Value>, of row: Row, to value: Value
    ) {
        if row[keyPath: field] != value { row[keyPath: field] = value }
    }

    private func fetchConversation(_ id: UUID) throws -> ConversationRecord? {
        var descriptor = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
