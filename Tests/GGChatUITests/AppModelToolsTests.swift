import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A conversation kept here picks which of the paired Mac's servers it
/// uses, under a master switch: a setting of the conversation, on with
/// nothing picked for a new one, offered only where the Mac said it offers
/// MCP servers' tools. Off, a question is a plain run, and one sent with
/// Draw a run with the drawing tool alone, and the picks are kept.
@MainActor
final class AppModelToolsTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: ""))
    }

    private func requests(_ hub: FakeRunHub) -> [ChatRequest] {
        hub.with { $0.starts.map(\.request) }
    }

    private func send(_ model: AppModel, _ text: String, draws: Bool = false, until count: Int) async throws {
        XCTAssertTrue(model.send(text, images: [], draws: draws))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == count }
    }

    /// A new conversation on a Mac that offers tools has the wrench, on with
    /// nothing picked. The master switch turns the tools off and on again,
    /// leaves the conversation's date alone, and a press that changes
    /// nothing writes nothing: a store that refuses every write is not
    /// asked.
    func testANewConversationIsOnWithNoServerPickedAndTheSwitchTurnsItOff() async throws {
        let store = RefusingStore()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub(), drawing: .offersTavily, store: store)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(conversation.toolChoice, ToolChoice())
        XCTAssertTrue(model.offersTools(for: conversation))
        let menu = model.toolsMenu(for: conversation)
        XCTAssertTrue(menu.isOn)
        XCTAssertEqual(menu.label, "Tools, none picked")
        XCTAssertEqual(menu.rows.map(\.picked), [false])

        model.setTools(on: false, for: conversation.id)
        let off = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(off.toolChoice.off)
        XCTAssertEqual(model.toolsMenu(for: off).label, "Tools, off")
        XCTAssertEqual(off.updatedAt, conversation.updatedAt)
        XCTAssertEqual(try store.loadConversations().first { $0.id == off.id }?.toolChoice.off, true)

        model.setTools(on: true, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.toolChoice.off, false)
        XCTAssertEqual(try store.loadConversations().first { $0.id == off.id }?.toolChoice.off, false)

        XCTAssertNil(model.lastError)
        store.refusesConversationSaves = true
        model.setTools(on: true, for: conversation.id)
        XCTAssertNil(model.lastError, "a press that changed nothing wrote the conversation")
        model.setTools(on: false, for: conversation.id)
        XCTAssertEqual(model.lastError, "the store refused", "a press that changed the switch wrote nothing")
    }

    /// Off, a question is a plain run read as the chat route's chunks, and
    /// one sent with Draw is a run that draws naming no server, read as an
    /// agent's. Turned on again, the next question names the pick it kept.
    func testOffSendsAPlainRunAndWithDrawOnlyTheDrawingToolAndKeepsThePicks() async throws {
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: .offersTavily)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.setServer(3, picked: true, for: id)
        model.setTools(on: false, for: id)
        try await send(model, "what is new in Swift?", until: 2)
        try await send(model, "a fox in snow", draws: true, until: 4)
        model.setTools(on: true, for: id)
        try await send(model, "and in cargo?", until: 6)

        let sent = requests(hub)
        XCTAssertEqual(sent.map(\.toolServers), [[], [], [3]])
        XCTAssertEqual(sent.map(\.runsAgentLoop), [false, true, true])
        XCTAssertEqual(sent.map(\.draws), [false, true, false])
        XCTAssertEqual(hub.with(\.readFrames), [.openai, .agent, .agent])
        XCTAssertEqual(model.selectedConversation?.toolChoice.picked, [3])
    }

    /// A question sent with Draw and the master off whose PUT lost its
    /// answer is put again under its id as it was first sent, naming none.
    func testAQuestionPutAgainAfterItsAnswerWasLostKeepsTheToolsOff() async throws {
        let hub = hub()
        hub.with { $0.putsLost = 1 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = .offersTavily
        let id = try XCTUnwrap(model.selectedConversationID)
        model.setServer(3, picked: true, for: id)
        model.setTools(on: false, for: id)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply to be read on") { Runs.settled(model) && hub.with { $0.starts.count } == 2 }
        let puts = requests(hub)
        XCTAssertEqual(puts.count, 2, "the lost PUT was not sent again")
        XCTAssertEqual(puts.map(\.toolsWord), ["none", "none"])
        XCTAssertEqual(puts.map(\.draws), [true, true])
        XCTAssertEqual(puts.first, puts.last, "the PUT sent again was another request")
    }

    /// A gglib reached by address, a Mac whose answer names no servers and
    /// one from before the list have no wrench and are named none of a
    /// conversation's picks. One not heard from has no wrench either, but
    /// may still open the picks, so it is named them as kept; a question it
    /// cannot be asked to draw yet goes without drawing.
    func testTheMenuIsHiddenWhereNoServerIsOfferedAndAnUnheardMacIsSentThePicksAsKept() async throws {
        let direct = hub()
        let (byAddress, config) = try await Runs.makeModel(behind: direct, direct: true)
        byAddress.drawings[config.id] = .offersTavily
        let shown = try XCTUnwrap(byAddress.selectedConversation)
        XCTAssertTrue(byAddress.toolsMenu(for: shown).isHidden)
        byAddress.setServer(3, picked: true, for: shown.id)
        try await send(byAddress, "what is new in Swift?", until: 2)
        XCTAssertEqual(requests(direct).map(\.toolServers), [[]])

        let none = Drawing(available: true, model: "flux-dev", mcpServers: [])
        for drawing in [none, DrawingRunTests.can] {
            let hub = hub()
            let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: drawing)
            let conversation = try XCTUnwrap(model.selectedConversation)
            XCTAssertTrue(model.toolsMenu(for: conversation).isHidden, String(describing: drawing))
            model.setServer(3, picked: true, for: conversation.id)
            try await send(model, "a fox in snow", draws: true, until: 2)
            XCTAssertEqual(requests(hub).map(\.toolServers), [[]], String(describing: drawing))
            XCTAssertEqual(requests(hub).map(\.draws), [drawing.available], String(describing: drawing))
        }

        let quiet = hub()
        quiet.with { $0.drawing = .failure(.transport("not yet")) }
        let (unheard, _) = try await DrawingRunTests.makeModel(behind: quiet, drawing: nil)
        let conversation = try XCTUnwrap(unheard.selectedConversation)
        XCTAssertTrue(unheard.toolsMenu(for: conversation).isHidden)
        unheard.setServer(3, picked: true, for: conversation.id)
        try await send(unheard, "a fox in snow", draws: true, until: 2)
        XCTAssertEqual(requests(quiet).map(\.toolServers), [[3]])
        XCTAssertEqual(requests(quiet).map(\.draws), [false])
        XCTAssertEqual(quiet.with(\.readFrames), [.agent], "a question naming a server was not an agent's")
    }

    /// After a relaunch, a question sent with Draw in a conversation that
    /// picked a server, whose `PUT` lost its answer, is put again before the
    /// Mac has said whether it offers servers. It names the pick as kept,
    /// and goes as `?kind=chat&tools=3&draw=true`, read here from the
    /// request itself; the Mac drops it if it no longer opens it.
    func testARelaunchedPutBeforeTheMacsAnswerNamesThePicksAsKept() async throws {
        let hub = hub()
        hub.with { $0.drawing = .failure(.transport("not yet")) }
        let store = InMemoryStore()
        let secrets = InMemorySecrets()
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(Runs.ticket)), defaultModel: "mock-27b")
        try store.save(provider: config)
        try secrets.setSecret(Runs.ticket, .ticket, for: config.id)
        try secrets.setSecret("secret-token", .token, for: config.id)
        let conversation = Conversation(
            providerID: config.id,
            messages: [
                Message(role: .user, content: "a fox in snow", createdAt: .distantPast, draws: true),
                Message(
                    role: .assistant, content: "", isPartial: true, createdAt: .distantPast, runID: "r",
                    runCursor: nil, runFrames: .agent),
            ], createdAt: .distantPast, updatedAt: .distantPast, toolChoice: ToolChoice(picked: [3]))
        try store.save(conversation: conversation)
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: store, secrets: secrets, log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: hub, registry: registry),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "tools.relaunch.\(UUID().uuidString)")!))
        model.load()
        try await Runs.until("the PUT sent again") { hub.with { $0.starts.count } >= 1 }
        XCTAssertNil(model.drawings[config.id], "the Mac's answer was known before the PUT")
        let put = try XCTUnwrap(hub.with { $0.starts.first })
        XCTAssertEqual(put.id, "r")
        XCTAssertEqual(put.request.toolServers, [3], "the PUT sent again did not name the pick")
        XCTAssertTrue(put.request.draws)
        XCTAssertTrue(put.request.runsAgentLoop)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueryRecorder.self]
        let wire = OpenAICompatibleProvider(
            baseURL: URL(string: "http://relaunch.tools.test/v1")!, session: URLSession(configuration: configuration))
        _ = try? await wire.startRun(id: put.id, put.request)
        let asked = QueryRecorder.asked.withLock { $0.first { $0.host() == "relaunch.tools.test" } }
        XCTAssertEqual(asked?.path(), "/v1/runs/r")
        XCTAssertEqual(asked?.query(), "kind=chat&tools=3&draw=true")
    }
}

/// Keeps the URL of every request it is sent and answers none, so the query
/// a request is put with can be read from the request itself.
private final class QueryRecorder: URLProtocol, @unchecked Sendable {
    static let asked = Mutex<[URL]>([])

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.asked.withLock { $0.append(url) } }
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}
