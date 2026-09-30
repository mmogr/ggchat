import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// An unreachable Mac's section shows the titles its list last showed and
/// when, kept on the provider's row; opening one says the Mac is
/// unreachable. The model's clock reads 22:13 UTC on 14 November 2023.
@MainActor
final class HubChatsSeenTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let seenAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let titles = FakeChatsHub.summaries.map { SeenHubChat(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }

    private func line(_ model: AppModel, _ id: UUID) -> String? {
        model.hubLine(for: id, locale: locale, calendar: calendar)
    }

    private func listed(
        _ hub: FakeChatsHub = FakeChatsHub(), store: any Store = InMemoryStore()
    ) async throws -> (AppModel, ProviderConfig) {
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub, store: store)
        try await AppModelRunTests.until("the list") {
            model.hubChats[config.id] == FakeChatsHub.summaries && model.hubListing.isEmpty
        }
        return (model, config)
    }

    func testAnUnreachableMacShowsTheTitlesItLastSawAndWhen() async throws {
        let (model, config) = try await listed()
        XCTAssertNil(line(model, config.id), "a reachable Mac said when it was last seen")
        XCTAssertEqual(model.mark(for: FakeChatsHub.summaries[0], on: config.id), .writing)

        await model.disconnectPipe(for: config.id, leaving: .closed)
        XCTAssertEqual(model.hubChats[config.id]?.map(\.title), ["Why the build broke", "New Chat"])
        XCTAssertEqual(line(model, config.id), "last seen 22:13")
        XCTAssertNil(model.mark(for: FakeChatsHub.summaries[0], on: config.id), "Writing from a Mac out of reach")
    }

    /// Opening a chat while its Mac cannot be reached asks nothing and says
    /// so; the pipe coming back reads it.
    func testOpeningOneWhileTheMacIsUnreachableSaysSo() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await listed(hub)
        await model.disconnectPipe(for: config.id, leaving: .closed)
        model.selection = .hub(providerID: config.id, chatID: 12)
        XCTAssertEqual(model.openedHubChat?.state, .unavailable("home is unreachable."))
        XCTAssertEqual(hub.with(\.opens), [])
        XCTAssertNil(model.lastError)

        await model.connectPipe(for: config)
        try await AppModelRunTests.until("the rows") {
            if case .read = model.openedHubChat?.state { return true }
            return false
        }
        XCTAssertEqual(hub.with(\.opens), [12])
    }

    /// A chat opened while its pipe is being dialled waits for the dial, and
    /// says the Mac is unreachable when the dial fails.
    func testAChatOpenedDuringADialThatFailsSaysTheMacIsUnreachable() async throws {
        let registry = LoopbackProviderRegistry()
        let gate = GatedConnector(registry: registry)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: gate,
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "HubChatsSeenTests.\(UUID().uuidString)")!),
            now: { self.seenAt })
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: "abc"))
        // A blank token: the mock refuses the dial once the gate lets it go.
        try model.addProvider(config, credentials: [.ticket: "pipe-ticket", .token: " "])
        let dial = Task { await model.connectPipe(for: config) }
        try await AppModelRunTests.until("the dial") { gate.arrivals == 1 }
        model.selection = .hub(providerID: config.id, chatID: 12)
        XCTAssertEqual(model.openedHubChat?.state, .reading)
        gate.open()
        await dial.value
        XCTAssertEqual(model.openedHubChat?.state, .unavailable("home is unreachable."))
    }

    /// Every list keeps its titles and the time over the ones before, and
    /// they outlive a relaunch, in which a Mac not dialled yet shows them.
    func testTheTitlesAreKeptAfterEveryListAndSurviveARelaunch() async throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        let providerID: UUID
        do {
            let opened = SwiftDataStore.open(at: scratch.location, log: NoopLogSink())
            XCTAssertNil(opened.notice, "the store was not kept on disk")
            let store = SwiftDataStore(container: opened.container)
            let hub = FakeChatsHub()
            let (model, config) = try await listed(hub, store: store)
            providerID = config.id
            XCTAssertEqual(try store.loadHubChats(forProvider: config.id), SeenHubChats(chats: titles, seenAt: seenAt))

            hub.with { $0.list = .success(HubChatList(chats: [FakeChatsHub.summaries[1]])) }
            await model.listHubChats(config.id)
            XCTAssertEqual(
                try store.loadHubChats(forProvider: config.id)?.chats, [titles[1]], "a list did not replace them")
            await model.disconnectPipe(for: config.id)
        }

        let reopened = SwiftDataStore.open(at: scratch.location, log: NoopLogSink())
        let registry = LoopbackProviderRegistry()
        // A blank token: the mock refuses the launch's quiet dial, so the Mac
        // stays out of reach while this device is still paired with it.
        let secrets = InMemorySecrets()
        try secrets.setSecret("pipe-ticket", .ticket, for: providerID)
        try secrets.setSecret(" ", .token, for: providerID)
        let model = AppModel(
            store: SwiftDataStore(container: reopened.container), secrets: secrets, log: NoopLogSink(),
            registry: registry, pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "HubChatsSeenTests.\(UUID().uuidString)")!),
            now: { self.seenAt.addingTimeInterval(60) })
        model.load()
        try await AppModelRunTests.until("the dial") { model.pipeStatus(for: providerID) == .closed }
        XCTAssertEqual(
            model.hubChats[providerID], [HubChatSummary(id: 9, title: "New Chat", updatedAt: "2026-09-29 18:02:41")])
        XCTAssertEqual(line(model, providerID), "last seen 22:13")
        XCTAssertNil(model.lastError)
    }

    /// Removing the provider deletes its row and the titles with it, in
    /// either store.
    func testRemovingTheProviderForgetsItsTitles() async throws {
        let stores: [any Store] = [SwiftDataStore(container: SwiftDataStore.inMemoryContainer()), InMemoryStore()]
        for store in stores {
            let (model, config) = try await listed(store: store)
            XCTAssertNotNil(try store.loadHubChats(forProvider: config.id), "\(store)")
            model.removeProvider(config.id)
            XCTAssertNil(try store.loadHubChats(forProvider: config.id), "\(store)")
            XCTAssertNil(model.hubChats[config.id])
            XCTAssertNil(line(model, config.id))
            XCTAssertEqual(model.hubProviders, [])
        }
    }

    /// A store the build before the titles wrote opens in this one with none,
    /// and one this build wrote, titles kept, opens under the earlier schema.
    func testAStoreOpensAcrossTheTitlesChangeInBothDirections() throws {
        let scratch = StoreScratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
        let earlierSchema = Schema([EarlierBuild.ProviderRecord.self, ConversationRecord.self, MessageRecord.self])
        func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
            let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        let kindData = try JSONEncoder().encode(ProviderConfig.Kind.pipe(ticketDigest: "abc"))

        let older = scratch.support.appending(path: "older.store")
        let id = UUID()
        do {
            let written = try container(earlierSchema, at: older)
            written.mainContext.insert(
                EarlierBuild.ProviderRecord(id: id, name: "home", kindData: kindData, createdAt: seenAt))
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        XCTAssertEqual(try opened.loadProviders().map(\.name), ["home"])
        XCTAssertNil(try opened.loadHubChats(forProvider: id))

        let newer = scratch.support.appending(path: "newer.store")
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(provider: ProviderConfig(id: id, name: "home", kind: .pipe(ticketDigest: "abc")))
            try store.save(hubChats: titles, seenAt: seenAt, forProvider: id)
        }
        let earlier = try container(earlierSchema, at: newer)
        let rows = try earlier.mainContext.fetch(FetchDescriptor<EarlierBuild.ProviderRecord>())
        XCTAssertEqual(rows.map(\.name), ["home"])
    }
}
