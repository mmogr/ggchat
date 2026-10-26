import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// A conversation kept here can turn the paired Mac's tools off: a setting
/// of the conversation, on until turned off, offered only where the Mac
/// said it offers MCP servers' tools (ADR 0013). Off, a question is a plain
/// run, and one sent with Draw a run with the drawing tool alone.
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

    /// A new conversation on a Mac that offers tools has the switch, on: a
    /// wrench, filled while on, with its state in its name. Pressed, it
    /// turns the tools off and on again, leaves the
    /// conversation's date alone, and a press that changes nothing writes
    /// nothing: a store that refuses every write is not asked.
    func testANewConversationHasTheToolsOnAndTheSwitchTurnsThemOff() async throws {
        let store = RefusingStore()
        let (model, _) = try await DrawingRunTests.makeModel(
            behind: hub(), drawing: Drawing.offersTavily, store: store)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(ToolsToggle.symbol(isOn: true), "wrench.and.screwdriver.fill")
        XCTAssertEqual(ToolsToggle.symbol(isOn: false), "wrench.and.screwdriver")
        XCTAssertEqual([ToolsToggle.label(isOn: true), ToolsToggle.label(isOn: false)], ["Tools, on", "Tools, off"])
        XCTAssertFalse(conversation.toolsOff)
        XCTAssertTrue(model.toolsOn(for: conversation))
        XCTAssertTrue(model.offersTools(for: conversation))

        model.setTools(on: false, for: conversation.id)
        let off = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(off.toolsOff)
        XCTAssertFalse(model.toolsOn(for: off))
        XCTAssertEqual(off.updatedAt, conversation.updatedAt)
        XCTAssertEqual(try store.loadConversations().first { $0.id == off.id }?.toolsOff, true)

        model.setTools(on: true, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.toolsOff, false)
        XCTAssertEqual(try store.loadConversations().first { $0.id == off.id }?.toolsOff, false)

        XCTAssertNil(model.lastError)
        store.refusesConversationSaves = true
        model.setTools(on: true, for: conversation.id)
        XCTAssertNil(model.lastError, "a press that changed nothing wrote the conversation")
        model.setTools(on: false, for: conversation.id)
        XCTAssertEqual(model.lastError, "the store refused", "a press that changed the switch wrote nothing")
    }

    /// Off, a question is a plain run read as the chat route's chunks, and
    /// one sent with Draw is a run that draws with the tools off, read as an
    /// agent's. Turned on again, the next question runs the tools.
    func testOffSendsAPlainRunAndWithDrawOnlyTheDrawingTool() async throws {
        let hub = hub()
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: Drawing.offersTavily)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.setTools(on: false, for: id)
        try await send(model, "what is new in Swift?", until: 2)
        try await send(model, "a fox in snow", draws: true, until: 4)
        model.setTools(on: true, for: id)
        try await send(model, "and in cargo?", until: 6)

        let sent = requests(hub)
        XCTAssertEqual(sent.map(\.toolsOff), [true, true, false])
        XCTAssertEqual(sent.map(\.runsTools), [false, false, true])
        XCTAssertEqual(sent.map(\.draws), [false, true, false])
        XCTAssertEqual(hub.with(\.readFrames), [.openai, .agent, .agent])
    }

    /// A question sent with Draw and the tools off whose PUT lost its answer
    /// is put again under its id as it was first sent, with the tools off.
    func testAQuestionPutAgainAfterItsAnswerWasLostKeepsTheToolsOff() async throws {
        let hub = hub()
        hub.with { $0.putsLost = 1 }
        let (model, config) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        model.drawings[config.id] = Drawing.offersTavily
        model.setTools(on: false, for: try XCTUnwrap(model.selectedConversationID))
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply to be read on") { Runs.settled(model) && hub.with { $0.starts.count } == 2 }
        let puts = requests(hub)
        XCTAssertEqual(puts.count, 2, "the lost PUT was not sent again")
        XCTAssertEqual(puts.map(\.toolsOff), [true, true])
        XCTAssertEqual(puts.first, puts.last, "the PUT sent again was another request")
    }

    /// A gglib from before `tools=none` refuses a question sent with Draw
    /// and the tools off, and the question shows its sentence, with Retry,
    /// since no reply came; it still draws, so Retry asks for the picture.
    func testAGglibThatRefusesNoneLeavesItsSentenceOnTheQuestion() async throws {
        let hub = hub()
        let refusal = ProviderError.server(status: 400, code: "invalid_request", message: "unknown tools: none")
        hub.with { $0.start = .refused(refusal) }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: Drawing.offersTavily)
        model.setTools(on: false, for: try XCTUnwrap(model.selectedConversationID))
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the refusal") { Runs.settled(model) && hub.with { $0.starts.count } == 1 }
        let messages = try XCTUnwrap(model.selectedConversation?.messages)
        XCTAssertEqual(messages.map(\.role), [.user], "a reply was kept for a refused run")
        XCTAssertEqual(messages.first?.failure?.message, "unknown tools: none")
        XCTAssertEqual(messages.first?.draws, true)
        XCTAssertEqual(requests(hub).map(\.toolsOff), [true])
        XCTAssertEqual(requests(hub).map(\.draws), [true])
    }

    /// A gglib reached by address, a Mac whose answer names no servers, one
    /// from before the list and one not heard from have no switch. A
    /// conversation stored off is sent to the first three as if it were on:
    /// none of them is ever told the tools are off. One not heard from may
    /// offer servers, so it is told, and a question it cannot be asked to
    /// draw yet is a plain run.
    func testTheSwitchIsHiddenAndOffNeverSentWhereNoToolsAreOffered() async throws {
        let direct = hub()
        let (byAddress, config) = try await Runs.makeModel(behind: direct, direct: true)
        byAddress.drawings[config.id] = Drawing.offersTavily
        let shown = try XCTUnwrap(byAddress.selectedConversation)
        XCTAssertFalse(byAddress.offersTools(for: shown))
        byAddress.setTools(on: false, for: shown.id)
        try await send(byAddress, "what is new in Swift?", until: 2)
        XCTAssertEqual(requests(direct).map(\.toolsOff), [false])

        let none = Drawing(available: true, model: "flux-dev", mcpServers: [])
        for drawing in [none, DrawingRunTests.can] {
            let hub = hub()
            let (model, _) = try await DrawingRunTests.makeModel(behind: hub, drawing: drawing)
            let conversation = try XCTUnwrap(model.selectedConversation)
            XCTAssertFalse(model.offersTools(for: conversation), String(describing: drawing))
            model.setTools(on: false, for: conversation.id)
            try await send(model, "a fox in snow", draws: true, until: 2)
            XCTAssertEqual(requests(hub).map(\.toolsOff), [false], String(describing: drawing))
            XCTAssertEqual(requests(hub).map(\.draws), [drawing.available], String(describing: drawing))
        }

        let quiet = hub()
        quiet.with { $0.drawing = .failure(.transport("not yet")) }
        let (unheard, _) = try await DrawingRunTests.makeModel(behind: quiet, drawing: nil)
        let conversation = try XCTUnwrap(unheard.selectedConversation)
        XCTAssertFalse(unheard.offersTools(for: conversation))
        unheard.setTools(on: false, for: conversation.id)
        try await send(unheard, "a fox in snow", draws: true, until: 2)
        XCTAssertEqual(requests(quiet).map(\.toolsOff), [true])
        XCTAssertEqual(requests(quiet).map(\.draws), [false])
        XCTAssertEqual(requests(quiet).map(\.runsTools), [false])
        XCTAssertEqual(quiet.with(\.readFrames), [.openai], "a question to a Mac not heard from was not a plain run")
    }

    /// After a relaunch, a question sent with Draw in a conversation with
    /// its tools off, whose `PUT` lost its answer, is put again before the
    /// Mac has said whether it offers servers. It keeps the tools off, and
    /// goes as `?kind=chat&tools=none&draw=true` (the query table's
    /// `off.draws.offered.test` row, read here from the request itself), so
    /// it never runs the tools the person turned off; a gglib from before
    /// `none` refuses it, as the refusal test shows.
    func testARelaunchedPutOfADrawQuestionBeforeTheMacsAnswerKeepsTheToolsOff() async throws {
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
            ], createdAt: .distantPast, updatedAt: .distantPast, toolsOff: true)
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
        XCTAssertTrue(put.request.toolsOff, "the PUT sent again does not keep the tools off")
        XCTAssertTrue(put.request.draws)
        XCTAssertFalse(put.request.runsTools)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueryRecorder.self]
        let wire = OpenAICompatibleProvider(
            baseURL: URL(string: "http://relaunch.tools.test/v1")!, session: URLSession(configuration: configuration))
        _ = try? await wire.startRun(id: put.id, put.request)
        let asked = QueryRecorder.asked.withLock { $0.first { $0.host() == "relaunch.tools.test" } }
        XCTAssertEqual(asked?.path(), "/v1/runs/r")
        XCTAssertEqual(asked?.query(), "kind=chat&tools=none&draw=true")
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
