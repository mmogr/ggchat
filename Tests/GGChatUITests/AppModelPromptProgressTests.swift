import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// gglib for these tests: answers `GET /v1/models` with a list that says it
/// is gglib at a host told so, and says nothing at any other, or holds it at
/// a host told to hold; and a chat request with one word, keeping the body
/// each chat request carried. Each test uses its own hosts.
private final class ProgressServer: URLProtocol, @unchecked Sendable {
    private static let gglibHosts = Mutex<Set<String>>([])
    private static let bodies = Mutex<[String: [Data]]>([:])
    private static let held = Mutex<[String: [ProgressServer]]>([:])

    static func saysGGLib(at host: String) {
        gglibHosts.withLock { _ = $0.insert(host) }
    }

    /// Holds each model list at `host` until `release(at:)`.
    static func hold(at host: String) {
        held.withLock { $0[host] = [] }
    }

    static func isHolding(at host: String) -> Bool {
        held.withLock { !($0[host] ?? []).isEmpty }
    }

    static func release(at host: String) {
        let waiting = held.withLock { held -> [ProgressServer] in
            defer { held[host] = nil }
            return held[host] ?? []
        }
        for server in waiting { server.respondWithModels(at: host) }
    }

    static func chatBodies(at host: String) -> [Data] {
        bodies.withLock { $0[host] ?? [] }
    }

    static func provider(at host: String) -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressServer.self]
        return OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, session: URLSession(configuration: configuration))
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        if url.path().hasSuffix("/models") {
            let isHeld = Self.held.withLock { held -> Bool in
                guard let waiting = held[host] else { return false }
                held[host] = waiting + [self]
                return true
            }
            if !isHeld { respondWithModels(at: host) }
            return
        }
        let body = Self.body(of: request)
        Self.bodies.withLock { $0[host] = ($0[host] ?? []) + [body] }
        respond(200, body: #"data: {"choices":[{"delta":{"content":"hi"},"index":0}]}"# + "\n\ndata: [DONE]\n\n")
    }

    /// A body reaches a protocol as a stream more often than as data.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
            data.append(buffer, count: count)
        }
        return data
    }

    private func respondWithModels(at host: String) {
        let gglib = Self.gglibHosts.withLock { $0.contains(host) }
        let said = gglib ? #","gglib":{"version":"0.35.0","features":["chats","runs","drawing","status"]}"# : ""
        respond(200, body: #"{"object":"list","data":[{"id":"Qwen3.8-27B"}]"# + said + "}")
    }

    private func respond(_ status: Int, body: String) {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Yields the events it is given, then ends if the last one is terminal and
/// otherwise holds the reply open.
private struct EventsProvider: Provider {
    let events: [ChatEvent]

    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            if case .finished? = events.last { continuation.finish() }
        }
    }
}

/// While gglib reads a long prompt, the reply says how far it has got.
final class AppModelPromptProgressTests: XCTestCase {
    /// modelpipe's normative vector 1, the shortest string that is a ticket.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    /// A model with one provider of `kind` and a conversation open on it. A
    /// server's address is answered by `server`; a pipe's far side is `pipe`.
    @MainActor
    private func makeModel(
        _ kind: ProviderConfig.Kind, server: (any Provider)? = nil, pipe: any Provider = MockProvider()
    ) throws -> (AppModel, ProviderConfig) {
        let registry = LoopbackProviderRegistry()
        if case .openAICompatible(let baseURL) = kind, let server { registry.register(server, at: baseURL) }
        let defaults = UserDefaults(suiteName: "AppModelPromptProgressTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: pipe, registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(name: "home", kind: kind, defaultModel: "Qwen3.8-27B")
        let credentials: [SecretKind: String] = config.isPipe ? [.ticket: ticket, .token: "secret-token"] : [:]
        try model.addProvider(config, credentials: credentials)
        model.newConversation()
        return (model, config)
    }

    /// A model on a server whose address `provider` answers.
    @MainActor
    private func makeModel(behind provider: any Provider) throws -> AppModel {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49998/v1"))
        return try makeModel(.openAICompatible(baseURL: url), server: provider).0
    }

    /// The one chat request `host` was sent, as JSON.
    private func sentRequest(at host: String) throws -> [String: Any] {
        let bodies = ProgressServer.chatBodies(at: host)
        XCTAssertEqual(bodies.count, 1, "\(host) was sent \(bodies.count) chat requests")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(bodies.first)) as? [String: Any])
    }

    /// A pipe is asked even when its list says nothing of gglib, since its
    /// far side is gglib. A server is asked once its list has said it is
    /// gglib, and not when the list said nothing or has not been read.
    @MainActor
    func testOnlyAPipeOrAServerWhoseListSaidGGLibIsAskedForProgress() async throws {
        let (piped, pipe) = try makeModel(
            .pipe(ticketDigest: Ticket.digest(ticket)), pipe: ProgressServer.provider(at: "pipe.progress.test"))
        await piped.connectPipe(for: pipe)
        await piped.refreshModels(for: pipe)
        XCTAssertFalse(piped.proxyStatusAvailable(for: pipe.id))
        try await XCTUnwrap(piped.send("hi")).value
        XCTAssertEqual(try sentRequest(at: "pipe.progress.test")["return_progress"] as? Bool, true)

        let servers = [
            (host: "gglib.progress.test", gglib: true, listed: true, asked: true),
            (host: "other.progress.test", gglib: false, listed: true, asked: false),
            (host: "unlisted.progress.test", gglib: true, listed: false, asked: false),
        ]
        for server in servers {
            if server.gglib { ProgressServer.saysGGLib(at: server.host) }
            let url = try XCTUnwrap(URL(string: "http://\(server.host)/v1"))
            let (model, config) = try makeModel(
                .openAICompatible(baseURL: url), server: ProgressServer.provider(at: server.host))
            if server.listed { await model.refreshModels(for: config) }
            try await XCTUnwrap(model.send("hi")).value
            let sent = try sentRequest(at: server.host)
            if server.asked {
                XCTAssertEqual(sent["return_progress"] as? Bool, true, "\(server.host) was not asked")
            } else {
                XCTAssertNil(sent["return_progress"], "\(server.host) is not known to be gglib and was asked")
            }
        }
    }

    /// An edit that moves a server to another address forgets what the old
    /// one's list said, and drops a list still on its way from it, so a
    /// server there that is not gglib is not asked. A rename keeps it.
    @MainActor
    func testAServerMovedAwayFromGGLibIsNotAskedForProgress() async throws {
        let hosts = ["moved-gglib", "moved-other", "held-gglib", "held-other"].map { "\($0).progress.test" }
        let urls = try hosts.map { try XCTUnwrap(URL(string: "http://\($0)/v1")) }
        ProgressServer.saysGGLib(at: hosts[0])
        ProgressServer.saysGGLib(at: hosts[2])
        ProgressServer.hold(at: hosts[2])

        let (answered, config) = try makeModel(
            .openAICompatible(baseURL: urls[0]), server: ProgressServer.provider(at: hosts[0]))
        answered.registry.register(ProgressServer.provider(at: hosts[1]), at: urls[1])
        await answered.refreshModels(for: config)
        var edited = config
        edited.name = "renamed"
        try answered.updateProvider(edited, credentials: [:])
        XCTAssertTrue(answered.proxyStatusAvailable(for: config.id), "a rename forgot what the list said")
        edited.kind = .openAICompatible(baseURL: urls[1])
        try answered.updateProvider(edited, credentials: [:])
        await answered.refreshModels(for: edited)
        try await XCTUnwrap(answered.send("hi")).value
        XCTAssertNil(try sentRequest(at: hosts[1])["return_progress"], "a moved server kept gglib's answer")

        // Moved while the list of the old address is held, then answered.
        let (waiting, heldConfig) = try makeModel(
            .openAICompatible(baseURL: urls[2]), server: ProgressServer.provider(at: hosts[2]))
        waiting.registry.register(ProgressServer.provider(at: hosts[3]), at: urls[3])
        let list = Task { await waiting.refreshModels(for: heldConfig) }
        for _ in 0..<5_000 where !ProgressServer.isHolding(at: hosts[2]) {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(ProgressServer.isHolding(at: hosts[2]), "the list never reached the server")
        var moved = heldConfig
        moved.kind = .openAICompatible(baseURL: urls[3])
        waiting.updateProvider(moved)
        ProgressServer.release(at: hosts[2])
        await list.value
        await waiting.refreshModels(for: moved)
        try await XCTUnwrap(waiting.send("hi")).value
        XCTAssertNil(try sentRequest(at: hosts[3])["return_progress"], "a list in flight to the old address was kept")
    }

    /// The live reply holds the latest frame while it waits. A reply that
    /// had progress is kept exactly as one that had none.
    @MainActor
    func testTheLiveReplyHoldsTheLatestProgressAndNothingOfItIsKept() async throws {
        let frames = [42, 53, 57].map { PromptProgress(processed: $0, total: 57) }
        let waiting = try makeModel(behind: EventsProvider(events: frames.map(ChatEvent.progress)))
        let task = try XCTUnwrap(waiting.send("hi"))
        for _ in 0..<200 where waiting.liveReply?.progress != frames.last {
            await Task.yield()
        }
        XCTAssertEqual(waiting.liveReply?.progress, frames.last, "the live reply did not hold the latest frame")
        waiting.stop()
        await task.value
        XCTAssertEqual(waiting.selectedConversation?.messages.map(\.role), [.user])

        let reply: [ChatEvent] = [.delta("Hello"), .finished(reason: "stop", usage: nil)]
        let withProgress = try makeModel(behind: EventsProvider(events: frames.map(ChatEvent.progress) + reply))
        let without = try makeModel(behind: EventsProvider(events: reply))
        for model in [withProgress, without] {
            try await XCTUnwrap(model.send("hi")).value
            XCTAssertNil(model.liveReply)
        }
        XCTAssertEqual(try kept(withProgress), try kept(without), "progress changed what was kept")
        XCTAssertEqual(try kept(withProgress).last?.content, "Hello")
    }

    /// What the store holds for the model's one conversation, ids aside.
    @MainActor
    private func kept(_ model: AppModel) throws -> [Message] {
        let conversation = try XCTUnwrap(model.store.loadConversations().first)
        return conversation.messages.map { message in
            var message = message
            message.id = Conversation.systemPromptMessageID
            return message
        }
    }
}
