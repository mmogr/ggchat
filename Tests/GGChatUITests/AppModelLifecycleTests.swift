import GGChatCore
import XCTest

@testable import GGChatUI

/// Yields one token and then never finishes, so a reply can be caught
/// mid-flight without any of it depending on a clock.
private struct HangingProvider: Provider {
    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.delta("half "))
        }
    }
}

/// What the app does when it goes away and when it comes back.
final class AppModelLifecycleTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
    private let serverURL = URL(string: "http://127.0.0.1:49998/v1")!

    @MainActor
    private func makeModel(registry: LoopbackProviderRegistry) -> AppModel {
        let defaults = UserDefaults(suiteName: "AppModelLifecycleTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    @MainActor
    private func addPipe(to model: AppModel) throws -> ProviderConfig {
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return config
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted { await Task.yield() }
    }

    /// The whole point: nothing is held across a background, and the way
    /// back is dialled rather than assumed.
    @MainActor
    func testGoingToTheBackgroundHangsUpEveryPipeAndComingBackDialsAgain() async throws {
        let registry = LoopbackProviderRegistry()
        let model = makeModel(registry: registry)
        let config = try addPipe(to: model)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        let session = try XCTUnwrap(model.pipeSession(for: config.id))

        await model.didEnterBackground()

        XCTAssertNil(model.pipeSession(for: config.id), "the pipe was held open across a background")
        XCTAssertEqual(
            model.pipeStatus(for: config.id), .closed,
            "the pill would have gone on saying Direct about a socket the system had taken back")
        XCTAssertNil(registry.provider(for: session.baseURL), "the session's port was left bound")

        await model.didBecomeActive()
        await waitForStatus(.direct, model, config.id)

        XCTAssertNotNil(model.pipeSession(for: config.id), "coming back left the pipe down with no way in")
        XCTAssertEqual(model.pipeStatus(for: config.id), .direct)
        XCTAssertEqual(model.diagnostics.foregroundResumes, 1, "ADR 0001's denominator still counts the resume")
    }

    /// A resume dials the pipes this app had, and only those. A provider
    /// nobody has opened a conversation for is left alone.
    @MainActor
    func testComingBackDoesNotDialAPipeTheAppNeverOpened() async throws {
        let model = makeModel(registry: LoopbackProviderRegistry())
        let config = try addPipe(to: model)

        await model.didBecomeActive()

        XCTAssertNil(model.pipeSession(for: config.id), "a pipe the user never opened was dialled on a resume")
        XCTAssertNil(model.pipeStatus(for: config.id))
        XCTAssertEqual(model.diagnostics.foregroundResumes, 1)
    }

    /// ADR 0002's worst case: a process killed while a reply is streaming
    /// used to leave the question with no answer under it and no error
    /// either. The partial is written on the way out instead.
    @MainActor
    func testGoingToTheBackgroundKeepsThePartialReplyInsteadOfLosingIt() async throws {
        let registry = LoopbackProviderRegistry()
        registry.register(HangingProvider(), at: serverURL)
        let model = makeModel(registry: registry)
        try model.addProvider(
            ProviderConfig(name: "server", kind: .openAICompatible(baseURL: serverURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        let streaming = try XCTUnwrap(model.send("go"))
        // The stream never ends by itself, so this test would hang rather
        // than fail if the cancellation went away; it is cancelled here
        // either way, after the assertions have had their say.
        defer { streaming.cancel() }
        for _ in 0..<200 where model.liveReply?.content.isEmpty != false { await Task.yield() }
        XCTAssertEqual(model.liveReply?.content, "half ", "the reply never started")

        await model.didEnterBackground()

        XCTAssertFalse(model.isStreaming, "the reply was left running into a process about to be suspended")
        let last = try XCTUnwrap(model.selectedConversation?.messages.last)
        XCTAssertEqual(last.role, .assistant, "the half that had arrived was thrown away")
        XCTAssertEqual(last.content, "half ")
        XCTAssertTrue(last.isPartial, "the partial was written as if it were the whole reply")
    }
}
