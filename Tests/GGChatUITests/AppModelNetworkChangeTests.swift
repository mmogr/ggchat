import Foundation
import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// What the app does when the network under the device moves: every pipe it
/// holds is told, so its endpoint can look for a path over the new network.
final class AppModelNetworkChangeTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(_ watcher: FakeNetworkWatcher) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelNetworkChangeTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: MockProvider(), registry: registry),
            networkWatcher: watcher,
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// A pipe provider, added and connected, with the session the model holds
    /// for it.
    @MainActor
    private func connectedPipe(
        named name: String, in model: AppModel
    ) async throws -> (ProviderConfig, MockPipeSession) {
        let config = ProviderConfig(
            name: name, kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        await model.connectPipe(for: config)
        for _ in 0..<200 where model.pipeStatus(for: config.id) != .direct { await Task.yield() }
        let session = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        return (config, session)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
    }

    /// The point of it: a change to the network reaches every pipe the app
    /// holds, not only the one on screen.
    @MainActor
    func testAChangeToTheNetworkTellsEveryLivePipe() async throws {
        let watcher = FakeNetworkWatcher()
        let model = makeModel(watcher)
        model.load()
        let (_, home) = try await connectedPipe(named: "home", in: model)
        let (_, office) = try await connectedPipe(named: "office", in: model)

        watcher.move()
        await waitUntil { home.networkChangeCount == 1 && office.networkChangeCount == 1 }

        XCTAssertEqual(home.networkChangeCount, 1, "the network moved and this pipe was not told")
        XCTAssertEqual(office.networkChangeCount, 1, "every pipe the app holds is told, not only one")
    }

    /// A pipe that has been hung up has no endpoint left to tell, and the
    /// model no longer holds it. The live one beside it is what shows the
    /// change was delivered at all.
    ///
    /// The network moves twice before anything is checked. The watcher does
    /// not start a second delivery until the first has reached every pipe the
    /// model holds, so once the live pipe has heard twice, a hung-up pipe that
    /// was still held has heard at least once, whichever order the dictionary
    /// put them in. Checking after one delivery caught it only when the
    /// hung-up pipe happened to come first.
    @MainActor
    func testAPipeThatWasHungUpIsNotTold() async throws {
        let watcher = FakeNetworkWatcher()
        let model = makeModel(watcher)
        model.load()
        let (goneConfig, gone) = try await connectedPipe(named: "gone", in: model)
        let (_, live) = try await connectedPipe(named: "live", in: model)
        await model.disconnectPipe(for: goneConfig.id)

        watcher.move()
        watcher.move()
        await waitUntil { live.networkChangeCount == 2 }

        XCTAssertEqual(live.networkChangeCount, 2, "the change was never delivered")
        XCTAssertEqual(gone.networkChangeCount, 0, "a pipe already hung up was told about the network")
    }

    /// Watching starts with `load()`, which runs as the app launches, and only
    /// once. Scene phases are no help for this: the one the app launches in is
    /// never reported as a change.
    @MainActor
    func testLoadingStartsWatchingTheNetworkOnce() {
        let watcher = FakeNetworkWatcher()
        let model = makeModel(watcher)
        XCTAssertEqual(watcher.timesAsked, 0, "building the model watches nothing yet")

        model.load()
        model.load()

        XCTAssertEqual(watcher.timesAsked, 1, "a second load started a second watch")
    }
}

/// A network that moves when a test says so.
final class FakeNetworkWatcher: NetworkPathWatching, Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let asked = Mutex(0)

    init() {
        let pair = AsyncStream<Void>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    /// How many times the app has asked to be told about changes.
    var timesAsked: Int {
        asked.withLock { $0 }
    }

    func changes() -> AsyncStream<Void> {
        asked.withLock { $0 += 1 }
        return stream
    }

    func move() {
        continuation.yield()
    }
}
