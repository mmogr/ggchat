import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A pipe connector that must not be asked: the model list never dials a
/// pipe to fill itself.
private struct NoDialConnector: PipeConnector {
    func connect(ticket: String, token: String) async throws -> any PipeSession {
        XCTFail("the model list dialled a pipe")
        throw PipeConnectError.unavailable
    }

    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe {
        throw PipeConnectError.unavailable
    }
}

/// A far machine whose model list the test changes between listings.
private final class ChangingModels: Provider {
    private let listed: Mutex<[ModelInfo]>

    init(_ models: [ModelInfo]) {
        listed = Mutex(models)
    }

    func set(_ models: [ModelInfo]) {
        listed.withLock { $0 = models }
    }

    func models() async throws -> [ModelInfo] {
        listed.withLock { $0 }
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { $0.finish() }
    }
}

/// The composer's model list: a section for each provider, in the
/// providers' order, filled without dialling a pipe or serving the engine,
/// a pipe that is down dimmed under the models it listed last, and a pick on
/// another provider moving the conversation there with that model.
@MainActor
final class ModelListTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let locale = Locale(identifier: "en_GB")
    private let serverURL = URL(string: "http://127.0.0.1:49982/v1")!
    private static let served = [
        ModelInfo(id: "Qwen3-4B", description: "qwen3 - 4B parameters, Q8_0"),
        ModelInfo(id: "flux-dev", capabilities: ["image_generation"]),
    ]

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// This iPhone on the mock engine and library, a paired Mac called
    /// "home" never dialled, and a server by address listing `served`, in
    /// that order, with a conversation on This iPhone.
    private struct Made {
        let model: AppModel
        let iPhone: ProviderConfig
        let home: ProviderConfig
        let server: ProviderConfig
    }

    private func makeModel(
        connector: (LoopbackProviderRegistry) -> any PipeConnector = { _ in NoDialConnector() }
    ) throws -> Made {
        let registry = LoopbackProviderRegistry()
        registry.register(MockProvider(models: Self.served), at: serverURL)
        let defaults = UserDefaults(suiteName: "ModelListTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector(registry), engine: MockEngine(registry: registry), library: MockLibrary(),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let iPhone = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        let home = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(home, credentials: [.ticket: ticket, .token: "secret-token"])
        let server = ProviderConfig(
            name: "server", kind: .openAICompatible(baseURL: serverURL), defaultModel: "server-default")
        try model.addProvider(server, credentials: [:])
        model.newConversation()
        return Made(model: model, iPhone: iPhone, home: home, server: server)
    }

    /// Waits, for up to ten seconds, until `done` holds, and answers whether
    /// it did: a pipe comes up, and lists, off the main actor.
    private func waitUntil(_ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    private func sections(_ model: AppModel) throws -> [ModelListSection] {
        model.modelListSections(for: try XCTUnwrap(model.selectedConversation), locale: locale, calendar: calendar)
    }

    /// Opening the list reads This iPhone's library and lists the server,
    /// and neither serves the engine nor dials the pipe. This iPhone's model
    /// is ticked and says its size until the engine has described it; the
    /// pipe has nothing listed; a model that draws is left out.
    func testEveryProviderIsASectionInTheirOrderFilledWithoutDiallingOrServing() async throws {
        let made = try makeModel()
        let (model, iPhone, home, server) = (made.model, made.iPhone, made.home, made.server)
        await model.relistModels().value
        XCTAssertNil(model.engineSession, "the list served the engine")
        XCTAssertNil(model.lastError)

        let listed = try sections(model)
        XCTAssertEqual(listed.map(\.id), [iPhone.id, home.id, server.id])
        XCTAssertEqual(listed.map(\.moves), [false, true, true])
        XCTAssertEqual(listed.map(\.state), ["not loaded", "not heard from yet", nil])
        XCTAssertEqual(listed.map(\.isListed), [true, false, true])
        XCTAssertEqual(listed.map(\.offersConnect), [false, true, false], "only the pipe with nothing offers Connect")
        XCTAssertEqual(
            listed[0].rows,
            [ModelListRow(modelID: MockEngine.model.id, detail: Sizes.download(1_073_741_824), isCurrent: true)])
        XCTAssertEqual(listed[1].rows, [])
        XCTAssertEqual(listed[2].rows, [ModelListRow(modelID: "Qwen3-4B", detail: "4B · Q8_0", isCurrent: false)])
        XCTAssertFalse(listed.contains(where: \.isStale))

        // Once the engine has listed its model, the row says what it said.
        await model.open(iPhone).value
        XCTAssertEqual(try sections(model).first?.rows.first?.detail, MockEngine.model.detailLine)
    }

    /// A pipe that is down keeps the models it listed last, dimmed, with
    /// when its machine was last heard; connected, they are not dimmed.
    func testAPipeThatIsDownShowsWhatItListedLastDimmed() throws {
        let made = try makeModel()
        let (model, home) = (made.model, made.home)
        model.modelsByProvider[home.id] = [ModelInfo(id: "gpt-oss-20b", description: "gpt-oss - 20B parameters, MXFP4")]
        var section = try XCTUnwrap(try sections(model).first { $0.id == home.id })
        XCTAssertTrue(section.isStale)
        XCTAssertEqual(section.rows.map(\.detail), ["20B · MXFP4"])
        XCTAssertEqual(section.state, "not heard from yet")

        model.setPipeStatus(.direct, for: home.id)
        section = try XCTUnwrap(try sections(model).first { $0.id == home.id })
        XCTAssertFalse(section.isStale)
        XCTAssertEqual(section.state, "connected")

        model.setPipeStatus(.closed, for: home.id)
        section = try XCTUnwrap(try sections(model).first { $0.id == home.id })
        XCTAssertTrue(section.isStale)
        XCTAssertEqual(section.state, model.lastHeardLine(for: home.id, locale: locale, calendar: calendar))
        XCTAssertTrue(section.state?.hasPrefix("last heard ") == true)
    }

    /// A model on another provider moves the conversation there with that
    /// model, not the provider's default, dropping the Thinking choice, the
    /// image model and the servers picked; one on its own provider is only
    /// chosen, and the tick follows.
    func testAPickOnAnotherProviderMovesTheConversationWithThatModel() throws {
        let made = try makeModel()
        let (model, server) = (made.model, made.server)
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.thinkingOff = true
        conversation.imageModelID = 3
        conversation.toolChoice = ToolChoice(off: true, picked: [3], seen: [3])
        model.update(conversation)

        model.pick(model: "Qwen3-4B", on: server.id, for: conversation.id)
        let moved = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(moved.providerID, server.id)
        XCTAssertEqual(moved.model, "Qwen3-4B")
        XCTAssertFalse(moved.thinkingOff)
        XCTAssertNil(moved.imageModelID)
        XCTAssertEqual(moved.toolChoice, ToolChoice(), "a move kept the servers picked on the machine left")
        XCTAssertEqual(
            model.providers.first { $0.id == server.id }?.defaultModel, "server-default",
            "a pick changed the provider's default")

        model.pick(model: "other-9b", on: server.id, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.providerID, server.id)
        XCTAssertEqual(model.selectedConversation?.model, "other-9b")
        model.modelsByProvider[server.id] = [ModelInfo(id: "other-9b")]
        let ticked = try sections(model).flatMap(\.rows).filter(\.isCurrent).map(\.modelID)
        XCTAssertEqual(ticked, ["other-9b"])
    }

    /// While a reply is still being written, a model on another provider
    /// moves nothing, and one on the conversation's own is still chosen.
    func testNothingMovesWhileAReplyIsWritten() throws {
        let made = try makeModel()
        let (model, iPhone, server) = (made.model, made.iPhone, made.server)
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages = [Message(role: .assistant, content: "", createdAt: .distantPast, runID: "r1")]
        model.update(conversation)
        XCTAssertFalse(model.canChangeProvider(of: conversation))

        model.pick(model: "Qwen3-4B", on: server.id, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.providerID, iPhone.id)
        XCTAssertEqual(model.selectedConversation?.model, MockEngine.model.id)

        model.pick(model: "another-phone-model", on: iPhone.id, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.model, "another-phone-model")
    }

    /// A conversation whose provider was removed gets one by picking any
    /// model, with no step of choosing a provider first.
    func testAConversationWithNoProviderGetsOneByAPick() throws {
        let made = try makeModel()
        let (model, iPhone, server) = (made.model, made.iPhone, made.server)
        let conversation = try XCTUnwrap(model.selectedConversation)
        model.removeProvider(iPhone.id)
        let orphan = try XCTUnwrap(model.selectedConversation)
        XCTAssertNil(model.provider(for: orphan))
        XCTAssertTrue(try sections(model).allSatisfy(\.moves))

        model.pick(model: "Qwen3-4B", on: server.id, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.providerID, server.id)
        XCTAssertEqual(model.selectedConversation?.model, "Qwen3-4B")
    }

    /// Connect on a pipe that is down and has listed nothing dials it, as
    /// the pill's Reconnect does, and its models are listed as it comes up,
    /// in place of Connect.
    func testConnectDialsAPipeWithNothingListedAndItsModelsArrive() async throws {
        let far = ChangingModels([ModelInfo(id: "gpt-oss-20b", description: "gpt-oss - 20B parameters, MXFP4")])
        let made = try makeModel { MockPipeConnector(sleeper: ImmediateSleeper(), provider: far, registry: $0) }
        let (model, home) = (made.model, made.home)
        XCTAssertEqual(try sections(model).first { $0.id == home.id }?.offersConnect, true)

        await model.connect(fromTheList: home.id)?.value
        let arrived = await waitUntil { !model.models(for: home.id).isEmpty }
        XCTAssertTrue(arrived, "the pipe's models were never listed after Connect")
        let section = try XCTUnwrap(try sections(model).first { $0.id == home.id })
        XCTAssertFalse(section.offersConnect)
        XCTAssertFalse(section.isStale)
        XCTAssertEqual(section.state, "connected")
        XCTAssertEqual(section.rows.map(\.modelID), ["gpt-oss-20b"])
        XCTAssertNil(model.lastError)
    }

    /// Opening the list asks a pipe that is up again, so a model added on
    /// its machine since it last listed joins the list.
    func testOpeningTheListRelistsAPipeThatIsUp() async throws {
        let far = ChangingModels([ModelInfo(id: "gpt-oss-20b")])
        let made = try makeModel { MockPipeConnector(sleeper: ImmediateSleeper(), provider: far, registry: $0) }
        let (model, home) = (made.model, made.home)
        await model.connect(fromTheList: home.id)?.value
        _ = await waitUntil { !model.models(for: home.id).isEmpty }
        XCTAssertTrue(model.sessionIsUp(home))

        far.set([ModelInfo(id: "gpt-oss-20b"), ModelInfo(id: "Qwen3-4B")])
        await model.relistModels().value
        XCTAssertEqual(
            try sections(model).first { $0.id == home.id }?.rows.map(\.modelID), ["gpt-oss-20b", "Qwen3-4B"])
    }
}
