import GGChatCore
import XCTest

@testable import GGChatUI

/// A store either half of which can be told to refuse, so what the app does
/// when a durable write will not go is not a guess.
@MainActor
private final class RefusingStore: Store {
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

/// A redeemer with a fixed answer, so the re-pairing path can be walked
/// with no machine on the other end of anything.
private struct StubRedeemer: PairingRedeemer {
    let outcome: Result<String, PairingError>

    func redeem(code: String, through baseURL: URL) async throws -> String {
        try outcome.get()
    }
}

/// Forgetting a provider, and re-credentialling one in place.
final class AppModelProviderTests: XCTestCase {
    /// modelpipe's normative vector 1 from `docs/ticket-format-v0.md`, and a
    /// second string of the same shape standing in for what the next
    /// `gglib remote enable` prints.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let newTicket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaadesk2na"

    @MainActor
    private func makeModel(
        store: any Store, secrets: any Secrets, redeemer: any PairingRedeemer = StubRedeemer(outcome: .success("key"))
    ) -> AppModel {
        let registry = LoopbackProviderRegistry()
        let defaults = UserDefaults(suiteName: "AppModelProviderTests.\(UUID().uuidString)")!
        return AppModel(
            store: store, secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            redeemer: redeemer, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
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
        store.refusesDeletes = true

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

    /// The edit that had no path into it at all: a fresh ticket for a machine
    /// already on the list. The id has to survive, because a conversation
    /// names its provider by that id and nothing repoints it.
    @MainActor
    func testEditingAPipesCredentialsKeepsItsIdAndSoItsConversations() throws {
        let secrets = InMemorySecrets()
        let model = makeModel(store: InMemoryStore(), secrets: secrets)
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])
        let conversation = model.newConversation()

        var edited = config
        edited.name = "desk"
        edited.kind = .pipe(ticketDigest: Ticket.digest(newTicket))
        try model.updateProvider(edited, credentials: [.ticket: newTicket, .token: "new-token"])

        XCTAssertEqual(model.providers.map(\.id), [config.id], "the provider was replaced rather than edited")
        XCTAssertEqual(model.providers.first?.name, "desk")
        XCTAssertEqual(model.providers.first?.kind, .pipe(ticketDigest: Ticket.digest(newTicket)))
        XCTAssertEqual(
            model.conversations.first(where: { $0.id == conversation.id })?.providerID, config.id,
            "the conversation was orphaned by an edit")
        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), newTicket)
        XCTAssertEqual(try secrets.secret(.token, for: config.id), "new-token")
    }

    /// A credential named but left empty is a field the form did not ask to
    /// change, not an instruction to clear the Keychain.
    @MainActor
    func testAnEmptyCredentialKeepsTheOneAlreadyStored() throws {
        let secrets = InMemorySecrets()
        let model = makeModel(store: InMemoryStore(), secrets: secrets)
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])

        var edited = config
        edited.name = "desk"
        try model.updateProvider(edited, credentials: [.ticket: "", .token: ""])

        XCTAssertEqual(model.providers.first?.name, "desk")
        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), ticket)
        XCTAssertEqual(try secrets.secret(.token, for: config.id), "old-token")
    }

    /// An edit that cannot be saved must put back exactly what it found. A
    /// provider left holding a new ticket beside an old token would dial one
    /// machine with another machine's key.
    @MainActor
    func testAnEditThatWillNotSaveLeavesTheOldCredentialsInPlace() throws {
        let secrets = InMemorySecrets()
        let store = RefusingStore()
        let model = makeModel(store: store, secrets: secrets)
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])
        store.refusesSaves = true

        var edited = config
        edited.name = "desk"
        edited.kind = .pipe(ticketDigest: Ticket.digest(newTicket))
        XCTAssertThrowsError(
            try model.updateProvider(edited, credentials: [.ticket: newTicket, .token: "new-token"]))

        XCTAssertEqual(
            try secrets.secret(.ticket, for: config.id), ticket,
            "the new ticket was left in the Keychain beside the old token")
        XCTAssertEqual(try secrets.secret(.token, for: config.id), "old-token")
        XCTAssertEqual(model.providers.first?.name, "home", "an edit that did not happen was shown as done")
        XCTAssertEqual(model.providers.first?.kind, config.kind)
    }

    /// The whole edit, through the door a user comes in by: paste what the
    /// machine printed this session, redeem the code for its key, dial the
    /// new ticket. The old one was never read again, so nothing would have
    /// noticed the ticket had changed without the redial.
    @MainActor
    func testRePairingRedeemsTheNewCodeAndDialsTheNewTicket() async throws {
        let secrets = InMemorySecrets()
        let model = makeModel(
            store: InMemoryStore(), secrets: secrets, redeemer: StubRedeemer(outcome: .success("far-machine-key")))
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])
        await model.connectPipe(for: config)
        let firstSession = try XCTUnwrap(model.pipeSession(for: config.id))

        var edited = config
        edited.kind = .pipe(ticketDigest: Ticket.digest(newTicket))
        try await model.updatePairedProvider(edited, ticket: newTicket, code: "483920")

        XCTAssertEqual(model.providers.map(\.id), [config.id], "the provider was replaced rather than re-paired")
        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), newTicket)
        XCTAssertEqual(
            try secrets.secret(.token, for: config.id), "far-machine-key",
            "the key the new code was traded for is the token; nothing was carried by hand")
        let session = try XCTUnwrap(model.pipeSession(for: config.id), "the new ticket was saved but never dialled")
        XCTAssertNotEqual(
            session.baseURL, firstSession.baseURL, "the old session was kept, so the new ticket did nothing")
        XCTAssertEqual(
            model.diagnostics.ticketDigests.count, 2, "a second machine is a second reading of the kill criterion")
    }

    /// A refused code leaves the provider exactly as it was: still pointing
    /// at the machine it was already paired with.
    @MainActor
    func testARefusedCodeLeavesTheProviderPairedWithTheMachineItHad() async throws {
        let secrets = InMemorySecrets()
        let model = makeModel(
            store: InMemoryStore(), secrets: secrets, redeemer: StubRedeemer(outcome: .failure(.refused)))
        let config = pipeConfig()
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "old-token"])

        var edited = config
        edited.kind = .pipe(ticketDigest: Ticket.digest(newTicket))
        do {
            try await model.updatePairedProvider(edited, ticket: newTicket, code: "000000")
            XCTFail("a refused code re-credentialled the provider")
        } catch let error as PairingError {
            XCTAssertEqual(error, .refused)
        }

        XCTAssertEqual(try secrets.secret(.ticket, for: config.id), ticket)
        XCTAssertEqual(try secrets.secret(.token, for: config.id), "old-token")
        XCTAssertEqual(model.providers.first?.kind, config.kind)
    }
}
