import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// What a paired Mac's section does when a list does not work, when a pull
/// finds the pipe up, when the pairing is gone, and while a chat on screen
/// is read again. The model's clock reads 22:13 UTC.
@MainActor
final class HubChatsOutcomeTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func line(_ model: AppModel, _ id: UUID) -> String? {
        model.hubLine(for: id, locale: locale, calendar: calendar)
    }

    private func listed(
        _ hub: FakeChatsHub, store: any Store = InMemoryStore()
    ) async throws -> (AppModel, ProviderConfig) {
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub, store: store)
        try await AppModelRunTests.until("the list") {
            model.hubChats[config.id] == FakeChatsHub.summaries && model.hubListing.isEmpty
        }
        return (model, config)
    }

    /// A list that fails, through a pipe that is up, keeps the titles, the
    /// time and the stored copy as they were, and the section says when they
    /// were seen instead of showing them as live.
    func testAFailedListKeepsWhatWasSeenAndSaysWhen() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let hub = FakeChatsHub()
        let (model, config) = try await listed(hub, store: store)
        XCTAssertNil(line(model, config.id))
        let seenAt = model.hubSeenAt[config.id]
        let stored = try store.loadHubChats(forProvider: config.id)
        XCTAssertNotNil(stored)
        let failures: [HubChatsFailure] = [
            .dropped(nil), .dropped(.server(status: 503, code: "chats_unavailable", message: "none")),
            .refused(.server(status: 405, code: nil, message: "no")), .refused(.decoding("odd")),
        ]
        for failure in failures {
            hub.with { $0.list = .failure(failure) }
            await model.listHubChats(config.id)
            XCTAssertEqual(model.hubChats[config.id], FakeChatsHub.summaries, "\(failure)")
            XCTAssertEqual(model.hubSeenAt[config.id], seenAt, "\(failure)")
            XCTAssertEqual(try store.loadHubChats(forProvider: config.id), stored, "\(failure)")
            XCTAssertEqual(line(model, config.id), "last seen 22:13", "\(failure)")
            XCTAssertNil(model.mark(for: FakeChatsHub.summaries[0], on: config.id), "\(failure)")
        }
        hub.with { $0.list = .success(HubChatList(chats: FakeChatsHub.summaries)) }
        await model.listHubChats(config.id)
        XCTAssertNil(line(model, config.id))
    }

    /// A pull lists again through a pipe that is already up.
    func testAPullListsAgainThroughAPipeThatIsUp() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await listed(hub)
        let lists = hub.with(\.lists)
        hub.with { $0.list = .success(HubChatList(chats: [FakeChatsHub.summaries[1]])) }
        await model.refreshHubChats()
        XCTAssertEqual(hub.with(\.lists), lists + 1)
        XCTAssertEqual(model.hubChats[config.id], [FakeChatsHub.summaries[1]])
    }

    /// A gglib with no chats route has no section, and is still asked on a
    /// pull, so an updated one gets its section back.
    func testAnOlderGglibHasNoSectionUntilItLists() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.list = .failure(.notFound) }
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub)
        try await AppModelRunTests.until("the 404") { model.hubListOutcome[config.id] == .tooOld }
        XCTAssertEqual(model.hubProviders, [])
        hub.with { $0.list = .success(HubChatList(chats: FakeChatsHub.summaries)) }
        await model.refreshHubChats()
        XCTAssertEqual(model.hubProviders.map(\.id), [config.id])
        XCTAssertEqual(model.hubChats[config.id], FakeChatsHub.summaries)
    }

    /// With its ticket gone from the Keychain the Mac is not unreachable: the
    /// pairing is gone, and the section and an opened chat say so.
    func testAMacWithNothingToDialWithSaysToPairAgain() async throws {
        let (model, _) = try await AppModelRunTests.makeModel(behind: FakeChatsHub())
        let orphan = ProviderConfig(name: "office", kind: .pipe(ticketDigest: "x"))
        try model.addProvider(orphan, credentials: [:])
        await model.refreshHubChats()
        let unpaired = "office is not paired with this phone any more. Pair again from the Mac."
        XCTAssertEqual(line(model, orphan.id), unpaired)
        model.selection = .hub(providerID: orphan.id, chatID: 12)
        XCTAssertEqual(model.openedHubChat?.state, .unavailable(unpaired))
    }

    /// Going to the background stops a refresh from dialling.
    func testTheBackgroundStopsARefreshFromDialling() async throws {
        let (model, config) = try await AppModelRunTests.makeModel(behind: FakeChatsHub())
        await model.disconnectPipe(for: config.id, leaving: .closed)
        let dials = model.dialGeneration[config.id]
        model.isAway = true
        await model.refreshHubChats()
        XCTAssertEqual(model.dialGeneration[config.id], dials, "a refresh dialled from the background")
        XCTAssertEqual(model.pipeStatus(for: config.id), .closed)
    }

    /// A chat on screen keeps its rows while its pipe comes back and it is
    /// read again, takes the new rows when they land, and keeps them when a
    /// later read does not work.
    func testAChatOnScreenKeepsItsRowsWhileItIsReadAgain() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await listed(hub)
        model.selection = .hub(providerID: config.id, chatID: 12)
        try await AppModelRunTests.until("the rows") { model.openedHubChat?.state.showsRows == true }
        let first = model.openedHubChat?.state

        await model.disconnectPipe(for: config.id, leaving: .closed)
        XCTAssertEqual(model.openedHubChat?.state, first, "the rows went with the pipe")
        let later = HubMessage(id: 44, conversationID: 12, role: "user", content: "And now?", createdAt: "f")
        hub.with {
            $0.holdsOpens = true
            $0.chats[12] = HubChatOpen(
                conversation: FakeChatsHub.opened.conversation, messages: FakeChatsHub.opened.messages + [later])
        }
        await model.connectPipe(for: config)
        try await AppModelRunTests.until("the read again") { hub.with(\.opens).count == 2 }
        XCTAssertEqual(model.openedHubChat?.state, first, "the rows left while the chat was read again")
        hub.with { $0.holdsOpens = false }
        try await AppModelRunTests.until("the new rows") {
            guard case .read(let rows)? = model.openedHubChat?.state else { return false }
            return rows.last?.content == "And now?"
        }
        let second = model.openedHubChat?.state
        await model.disconnectPipe(for: config.id, leaving: .closed)
        hub.with { $0.openFailure = .dropped(nil) }
        await model.connectPipe(for: config)
        try await AppModelRunTests.until("the failed read") {
            hub.with(\.opens).count == 3 && model.hubReading == nil
        }
        XCTAssertEqual(model.openedHubChat?.state, second, "a read that failed took the rows away")
    }
}
