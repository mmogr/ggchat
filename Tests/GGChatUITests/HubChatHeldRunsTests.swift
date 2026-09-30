import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The provider row as the build before held runs declared it, for opening a
/// store across the change in both directions.
enum BeforeHeldRuns {
    @Model
    final class ProviderRecord {
        @Attribute(.unique) var uuid: UUID
        var name: String
        var kindData: Data
        var defaultModel: String?
        var createdAt: Date
        var lastHeard: Date?
        var hubChatsData: Data?
        var hubSeenAt: Date?

        init(id: UUID, name: String, kindData: Data, createdAt: Date) {
            self.uuid = id
            self.name = name
            self.kindData = kindData
            self.createdAt = createdAt
        }
    }
}

/// The runs a Mac is writing replies in that this phone sent for are kept
/// on the provider's row, their id and chat and nothing else: a launch reads
/// them on from their start, and a list that no longer names one forgets it.
@MainActor
final class HubChatHeldRunsTests: XCTestCase {
    /// A model on a store that holds a paired Mac with `runs`, launched.
    private func launched(
        holding runs: [HeldHubRun], behind hub: FakeChatsHub, store: InMemoryStore
    ) async throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: hub, registry: registry),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "HubChatHeldRunsTests.\(UUID().uuidString)")!))
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: "abc"))
        try model.addProvider(config, credentials: [.ticket: "pipe-ticket", .token: "secret-token"])
        try store.save(hubRuns: runs, forProvider: config.id)
        model.load()
        try await AppModelRunTests.until("the list") { model.hubChats[config.id] != nil && model.hubListing.isEmpty }
        return (model, config)
    }

    /// A launch has none of the reply's text, so opening its chat reads the
    /// run from its start; it asks for no second turn.
    func testALaunchReadsTheRunItKeptFromItsStartWhenItsChatOpens() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        let run = HeldHubRun(runID: "chat-5b1e", chatID: 12)
        let (model, config) = try await launched(holding: [run], behind: hub, store: store)
        XCTAssertEqual(model.hubReplies.map(\.runID), ["chat-5b1e"])
        XCTAssertEqual(hub.runs.with(\.reads).count, 0, "a chat not open was read")

        let reply = try XCTUnwrap(model.hubReplies.first)
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await AppModelRunTests.until("the end") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.id) }, ["chat-5b1e"])
        XCTAssertEqual(hub.runs.with { $0.reads.map(\.after) }, [0])
        XCTAssertEqual(reply.content, "Pin the version.")
        XCTAssertEqual(hub.with(\.turns).count, 0)
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [])
    }

    /// A list whose chat no longer names the kept run as live says the run
    /// has ended: it is forgotten without being read.
    func testAListThatNoLongerNamesTheRunForgetsIt() async throws {
        let store = InMemoryStore()
        let hub = FakeChatsHub()
        let (model, config) = try await launched(
            holding: [HeldHubRun(runID: "ended-long-ago", chatID: 12)], behind: hub, store: store)
        XCTAssertEqual(model.hubReplies.count, 0)
        XCTAssertEqual(try store.loadHubRuns(forProvider: config.id), [])
        XCTAssertEqual(hub.runs.with(\.reads).count, 0)
    }

    /// A store the build before held runs wrote opens in this one with none,
    /// and one this build wrote, runs kept, opens under the earlier schema.
    /// The runs outlive a reopening, and go with the provider's row.
    func testAStoreOpensAcrossTheHeldRunsChangeInBothDirections() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        let earlierSchema = Schema([BeforeHeldRuns.ProviderRecord.self, ConversationRecord.self, MessageRecord.self])
        func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
            let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        let kind = ProviderConfig.Kind.pipe(ticketDigest: "abc")
        let runs = [HeldHubRun(runID: "run-1", chatID: 12), HeldHubRun(runID: "run-2", chatID: 9)]

        let older = scratch.support.appending(path: "older.store")
        let id = UUID()
        do {
            let written = try container(earlierSchema, at: older)
            written.mainContext.insert(
                BeforeHeldRuns.ProviderRecord(
                    id: id, name: "home", kindData: try JSONEncoder().encode(kind), createdAt: .distantPast))
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        XCTAssertEqual(try opened.loadProviders().map(\.name), ["home"])
        XCTAssertEqual(try opened.loadHubRuns(forProvider: id), [])

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(provider: ProviderConfig(id: id, name: "home", kind: kind))
            try store.save(hubRuns: runs, forProvider: id)
            try store.save(hubRuns: runs, forProvider: UUID())
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadHubRuns(forProvider: id), runs)
            try store.deleteProvider(id: id)
            XCTAssertEqual(try store.loadHubRuns(forProvider: id), [])
            try store.save(provider: ProviderConfig(id: id, name: "home", kind: kind))
            try store.save(hubRuns: runs, forProvider: id)
        }
        let earlier = try container(earlierSchema, at: newer)
        let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeHeldRuns.ProviderRecord>())
        XCTAssertEqual(rows.map(\.name), ["home"])
    }
}
