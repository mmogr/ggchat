import Foundation
import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// Records each pause the app asks for between read-ons. It returns at once
/// when `immediate`, and otherwise never, so a test that does not ask for
/// read-ons after a pause sees none.
final class ReadOnSleeper: Sleeper {
    let immediate: Bool
    private let asked = Mutex<[Duration]>([])

    init(immediate: Bool) {
        self.immediate = immediate
    }

    var pauses: [Duration] {
        asked.withLock { $0 }
    }

    func sleep(for duration: Duration) async throws {
        asked.withLock { $0.append(duration) }
        if immediate {
            await Task.yield()
        } else {
            try await Task.sleep(for: .seconds(3_600))
        }
    }
}

extension AppModelRunTests {
    /// A model on `hub`, and a conversation open on it: through a pipe,
    /// dialled, or with `direct`, at an address that answered the status
    /// probe as gglib.
    @MainActor
    static func makeModel(
        behind hub: any Provider, store: any Store = InMemoryStore(), log: any LogSink = NoopLogSink(),
        sleeper: any Sleeper = ReadOnSleeper(immediate: false), direct: Bool = false
    ) async throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelRunTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: log, registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: hub, registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleeper: sleeper)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49996/v1"))
        let kind: ProviderConfig.Kind =
            direct ? .openAICompatible(baseURL: url) : .pipe(ticketDigest: Ticket.digest(ticket))
        let config = ProviderConfig(name: "home", kind: kind, defaultModel: "mock-27b")
        if direct {
            registry.register(hub, at: url)
            try model.addProvider(config, credentials: [:])
            model.proxyStatusAvailability[config.id] = true
        } else {
            try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
            await model.connectPipe(for: config)
            try await until { model.pipeStatus(for: config.id) == .direct }
        }
        model.newConversation()
        return (model, config)
    }

    /// Yields until `condition` holds, and fails the test when it never does.
    @MainActor
    static func until(
        _ what: String = "the condition", file: StaticString = #filePath, line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<5_000 where !condition() { await Task.yield() }
        if !condition() { XCTFail("\(what) never held", file: file, line: line) }
    }

    /// The last message of the open conversation.
    @MainActor
    static func last(_ model: AppModel) throws -> Message {
        try XCTUnwrap(model.selectedConversation?.messages.last)
    }

    /// Whether the open conversation has settled: nothing in flight, and no
    /// reply still being written.
    @MainActor
    static func settled(_ model: AppModel) -> Bool {
        model.liveReply == nil && model.selectedConversation?.messages.contains(where: \.isBeingWritten) == false
    }
}
