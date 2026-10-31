import Foundation
import GGChatCore
import SwiftData

/// Owns its container: a `ModelContext` whose container has been released
/// traps on the next fetch, so the two are kept together here.
public final class SwiftDataStore: Store {
    public let container: ModelContainer
    let context: ModelContext
    public private(set) var hiddenChats = 0

    public init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    public static let schema = Schema([
        ProviderRecord.self, ConversationRecord.self, MessageRecord.self, ImageRecord.self,
    ])

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

    /// A chat holding a turn whose role this build does not know, one a
    /// later build wrote, is left out whole and counted in `hiddenChats`.
    /// Read as a question, that turn would be shown and sent as one; and a
    /// chat loaded without it would lose it, since a save deletes the rows a
    /// conversation no longer holds. Left out, it is never saved over. So
    /// every row's role is read here, even if a list one day loads without
    /// the messages.
    public func loadConversations() throws -> [Conversation] {
        let records = try context.fetch(FetchDescriptor<ConversationRecord>())
        var hidden = 0
        defer { hiddenChats = hidden }
        return records.compactMap { record in
            let stored = record.messages.sorted { $0.order < $1.order }
            let roles = stored.compactMap { Role(rawValue: $0.role) }
            guard roles.count == stored.count else {
                hidden += 1
                return nil
            }
            return Conversation(
                id: record.uuid, title: record.title, providerID: record.providerID, model: record.model,
                messages: zip(stored, roles).map { message, role in
                    Message(
                        id: message.uuid, role: role, content: message.content,
                        reasoning: message.reasoning, isPartial: message.isPartial,
                        failure: Self.failure(from: message.failureData), createdAt: message.createdAt,
                        runID: message.runID, runCursor: message.runCursor.flatMap(UInt32.init(exactly:)),
                        images: Self.images(from: message.imagesData), originID: message.originID,
                        draws: message.draws ?? false,
                        runFrames: message.runFrames.flatMap(RunFrames.init(rawValue:)),
                        exchanges: Self.exchanges(from: message.exchangesData))
                },
                systemPrompt: record.systemPrompt, createdAt: record.createdAt, updatedAt: record.updatedAt,
                hasUnreadReply: record.hasUnreadReply ?? false, context: Self.reading(from: record.contextData),
                thinkingOff: record.thinkingOff ?? false, branchOf: record.branchOf, family: record.family,
                imageModelID: record.imageModelID.flatMap(UInt64.init(exactly:)),
                toolChoice: Self.toolChoice(from: record.toolChoiceData))
        }
    }

    /// Then deletes the images no turn names any more, of those this save
    /// took off a turn.
    public func save(conversation: Conversation) throws {
        let dropped = try write(conversation)
        try context.save()
        try deleteImages(noTurnNames: dropped)
    }

    /// Brings one conversation's rows in line with it, without saving them.
    ///
    /// A field is assigned only when it differs from the row's, because a
    /// `@Model` setter marks its row changed even for the value it already
    /// holds: every save used to mark every row of its conversation changed,
    /// twice a turn, though only one or two had changed (#139). A failure is
    /// encoded only when it is not the one the row already holds. Apart from
    /// `save(conversation:)` so a test can look at what a write marked before
    /// it is saved. Answers the ids of the images it took off a turn.
    @discardableResult
    func write(_ conversation: Conversation) throws -> Set<String> {
        let record = try conversationRow(for: conversation)
        var existing = Dictionary(record.messages.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var dropped = Set<String>()
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
                let held = Self.images(from: row.imagesData)
                if held != message.images {
                    dropped.formUnion(held.map(\.id))
                    row.imagesData = try Self.data(of: message.images)
                }
                Self.assign(\.draws, of: row, to: message.draws ? true : nil)
                Self.assign(\.runFrames, of: row, to: message.runFrames?.rawValue)
                if Self.exchanges(from: row.exchangesData) != message.exchanges {
                    row.exchangesData = try Self.data(of: message.exchanges)
                }
                Self.assign(\.order, of: row, to: order)
            } else {
                let row = try Self.row(for: message, at: order)
                row.conversation = record
                context.insert(row)
            }
        }
        for orphan in existing.values {
            dropped.formUnion(Self.images(from: orphan.imagesData).map(\.id))
            context.delete(orphan)
        }
        return dropped
    }

    /// The conversation's own row, brought in line with it field by field,
    /// or a new one inserted for it.
    private func conversationRow(for conversation: Conversation) throws -> ConversationRecord {
        if let record = try fetchConversation(conversation.id) {
            Self.assign(\.title, of: record, to: conversation.title)
            Self.assign(\.providerID, of: record, to: conversation.providerID)
            Self.assign(\.model, of: record, to: conversation.model)
            Self.assign(\.systemPrompt, of: record, to: conversation.systemPrompt)
            Self.assign(\.hasUnreadReply, of: record, to: conversation.hasUnreadReply)
            Self.assign(\.thinkingOff, of: record, to: conversation.thinkingOff)
            Self.assign(\.branchOf, of: record, to: conversation.branchOf)
            Self.assign(\.family, of: record, to: conversation.family)
            Self.assign(\.imageModelID, of: record, to: conversation.imageModelID.flatMap(Int.init(exactly:)))
            Self.assign(\.updatedAt, of: record, to: conversation.updatedAt)
            if Self.reading(from: record.contextData) != conversation.context {
                record.contextData = try conversation.context.map { try JSONEncoder().encode($0) }
            }
            if Self.toolChoice(from: record.toolChoiceData) != conversation.toolChoice {
                record.toolChoiceData = try Self.data(of: conversation.toolChoice)
            }
            return record
        }
        let record = ConversationRecord(
            id: conversation.id, title: conversation.title, providerID: conversation.providerID,
            model: conversation.model, createdAt: conversation.createdAt, updatedAt: conversation.updatedAt,
            systemPrompt: conversation.systemPrompt, hasUnreadReply: conversation.hasUnreadReply,
            contextData: try conversation.context.map { try JSONEncoder().encode($0) },
            thinkingOff: conversation.thinkingOff, branchOf: conversation.branchOf, family: conversation.family,
            imageModelID: conversation.imageModelID.flatMap(Int.init(exactly:)),
            toolChoiceData: try Self.data(of: conversation.toolChoice))
        context.insert(record)
        return record
    }

    /// A new row holding `message`, at `order` in its conversation.
    private static func row(for message: Message, at order: Int) throws -> MessageRecord {
        MessageRecord(
            id: message.id, role: message.role.rawValue, content: message.content,
            reasoning: message.reasoning, isPartial: message.isPartial, createdAt: message.createdAt,
            order: order, failureData: try message.failure.map { try JSONEncoder().encode($0) },
            runID: message.runID, runCursor: message.runCursor.map(Int.init),
            imagesData: try Self.data(of: message.images), originID: message.originID,
            draws: message.draws ? true : nil, runFrames: message.runFrames?.rawValue,
            exchangesData: try Self.data(of: message.exchanges))
    }

    /// With its images that no other conversation names.
    public func deleteConversation(id: UUID) throws {
        if let record = try fetchConversation(id) {
            let named = Set(record.messages.flatMap { Self.images(from: $0.imagesData).map(\.id) })
            context.delete(record)
            try context.save()
            try deleteImages(noTurnNames: named)
        }
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
