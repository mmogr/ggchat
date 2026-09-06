import GGChatCore
import XCTest

@testable import GGChatUI

/// A store whose provider delete refuses, so what the app does when the
/// durable half of a removal will not go is not a guess.
@MainActor
private final class RefusingStore: Store {
    struct Refused: Error {}

    let inner = InMemoryStore()

    func loadProviders() throws -> [ProviderConfig] {
        try inner.loadProviders()
    }

    func save(provider: ProviderConfig) throws {
        try inner.save(provider: provider)
    }

    func deleteProvider(id: UUID) throws {
        throw Refused()
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

/// Adding, forgetting and re-credentialling a provider.
final class AppModelProviderTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(store: any Store, secrets: any Secrets) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelProviderTests.\(UUID().uuidString)")!
        return AppModel(
            store: store, secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    private func pipeConfig() -> ProviderConfig {
        ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
    }

    /// The removal that used to leave the worst of both halves: credentials
    /// gone, row still there, and the next launch showing a provider that
    /// can never connect again.
    @MainActor
    func testAProviderWhoseRecordWillNotDeleteKeepsItsCredentials() throws {
        let secrets = InMemorySecrets()
        let store = RefusingStore()
        let model = makeModel(store: store, secrets: secrets)
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])

        model.removeProvider(config.id)

        XCTAssertEqual(
            model.providers.map(\.id), [config.id],
            "the row survived the delete, so the provider has to be back on the list it is still in")
        XCTAssertEqual(try store.loadProviders().map(\.id), [config.id])
        XCTAssertEqual(
            try secrets.secret(.token, for: config.id), "secret-token",
            "the credentials went first, so the next load would resurrect a provider that can never connect")
        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), ticket)
        XCTAssertNotNil(model.lastError, "a removal that did not happen was not reported")
    }

    /// And when the record does go, the credentials go with it.
    @MainActor
    func testRemovingAProviderTakesItsRecordAndItsCredentialsTogether() throws {
        let secrets = InMemorySecrets()
        let store = InMemoryStore()
        let model = makeModel(store: store, secrets: secrets)
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])

        model.removeProvider(config.id)

        XCTAssertTrue(model.providers.isEmpty)
        XCTAssertTrue(try store.loadProviders().isEmpty)
        XCTAssertNil(try secrets.secret(.ticket, for: config.id))
        XCTAssertNil(try secrets.secret(.token, for: config.id))
        XCTAssertNil(model.lastError)
    }
}
