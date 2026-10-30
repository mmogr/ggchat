import Foundation
import GGChatCore
import GGLib
import XCTest

@testable import GGChatLocal
@testable import GGChatUI

/// The app model on gglib's engine type, with the binding faked under it:
/// the same lazy serve, load and background shutdown as
/// `AppModelEngineLifecycleTests` walk on the mock engine, through
/// `GglibEngine`'s session and its watch rather than the mock's.
@MainActor
final class AppModelGglibEngineTests: XCTestCase {
    private let modelName = "tinygemma3-Q8_0"
    private let address = URL(string: "http://127.0.0.1:49170/v1")!

    /// A provider at the fake server's address that loads the model, as
    /// gglib's engine loads it within the first request naming it, before
    /// the mock's reply. A model already ready is not loaded again.
    private struct LoadsOnChat: Provider {
        let server: @Sendable () -> FakeServer?
        let model: String
        let replying = MockProvider(contextSize: 4_096)

        func models() async throws -> [ModelInfo] {
            [ModelInfo(id: model, ownedBy: "gglib")]
        }

        func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
            if let server = server() {
                server.move(to: .loading(model: model, fraction: 0.5))
                server.move(to: .ready(model: model, nCtx: 4_096))
            }
            return replying.stream(request)
        }
    }

    private final class Served: @unchecked Sendable {
        private let lock = NSLock()
        private var servers: [FakeServer] = []

        func add(_ server: FakeServer) {
            lock.withLock { servers.append(server) }
        }

        var all: [FakeServer] { lock.withLock { servers } }
        var last: FakeServer? { all.last }
    }

    /// An app model whose engine is gglib's over a fake library: each serve
    /// is a new fake server at one address, which answers as `LoadsOnChat`.
    private func makeModel() -> (AppModel, Served) {
        let served = Served()
        let library = FakeLibrary(serving: {
            let server = FakeServer.make()
            served.add(server)
            return server
        })
        let registry = LoopbackProviderRegistry()
        registry.register(LoadsOnChat(server: { served.last }, model: modelName), at: address)
        let defaults = UserDefaults(suiteName: "AppModelGglibEngineTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: GglibEngine(isAvailable: true) { library }, library: MockLibrary(),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        return (model, served)
    }

    /// Waits, for up to `limit`, until `done` holds, and answers whether it
    /// did, for `AppModelEngineTests.waitUntil`'s reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// The first send serves gglib's engine, which loads the model within
    /// the request; the pill reads Ready for the model as gglib names it,
    /// and the reply raises the ring.
    func testAFirstSendServesGglibsEngineAndThePillReadsReady() async throws {
        let (model, served) = makeModel()
        let config = try model.addThisIPhone(defaultModel: modelName)
        let conversation = model.newConversation(with: config)
        XCTAssertNil(model.engineSession, "adding This iPhone served its engine")

        try await XCTUnwrap(model.send("hi"), "a send on This iPhone was refused").value
        XCTAssertEqual(served.all.count, 1, "the send did not serve the engine once")
        XCTAssertEqual(model.selectedConversation?.messages.last?.content, MockProvider.sampleScript.text)
        let ready = await waitUntil { model.sessionStatus(for: conversation) == .engine(.ready) }
        XCTAssertTrue(ready, "the pill does not read Ready: \(String(describing: model.engineStatus))")
        XCTAssertEqual(model.engineStatus, .ready(model: modelName, nCtx: 4_096))
        XCTAssertEqual(model.selectedConversation?.context?.size, 4_096)
        await model.shutDownEngine()
    }

    /// The background puts gglib's engine down, and its watch ends; coming
    /// back serves nothing, and the next send serves it afresh.
    func testTheBackgroundPutsGglibsEngineDownAndTheNextSendServesAgain() async throws {
        let (model, served) = makeModel()
        let config = try model.addThisIPhone(defaultModel: modelName)
        let conversation = model.newConversation(with: config)
        try await XCTUnwrap(model.send("hi")).value
        let first = try XCTUnwrap(served.last)

        await model.scene(.background).value
        XCTAssertEqual(first.shutdowns, 1, "the background did not shut gglib's engine down")
        XCTAssertNil(model.engineSession)
        await model.scene(.foreground).value
        XCTAssertEqual(served.all.count, 1, "coming back served the engine")
        XCTAssertEqual(model.sessionStatus(for: conversation), .engine(.notLoaded))

        try await XCTUnwrap(model.send("again"), "a send after coming back was refused").value
        XCTAssertEqual(served.all.count, 2, "the send did not serve the engine afresh")
        let ready = await waitUntil { model.sessionStatus(for: conversation) == .engine(.ready) }
        XCTAssertTrue(ready, "the pill does not read Ready after the second load")
        await model.shutDownEngine()
    }
}
