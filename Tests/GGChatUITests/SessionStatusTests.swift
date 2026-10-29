import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// The status pill beside a conversation's model, which says how its pipe is
/// or how this device's engine is with its model: the words for each state,
/// what VoiceOver hears, which conversations have a pill at all, and a model
/// the engine refused as too big.
@MainActor
final class SessionStatusTests: XCTestCase {
    private func makeModel(engine: any LocalEngine, registry: LoopbackProviderRegistry) -> AppModel {
        let defaults = UserDefaults(suiteName: "SessionStatusTests.\(UUID().uuidString)")!
        return AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: engine, library: MockLibrary(), diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// Each of the engine's states in a few words with a memory chip, read
    /// as "Model …"; a pipe's as before, read as "Connection …". Only
    /// Reconnect and Load again are tinted, and a pipe connecting and a model
    /// loading animate.
    func testThePillSaysEachStateInAFewWords() {
        let engine: [(SessionStatus.ModelState, String)] = [
            (.notLoaded, "Not loaded"), (.loading(fraction: 0.4), "Loading 40%"), (.ready, "Ready"),
            (.failed, "Load again"), (.tooBig, "Too big"),
        ]
        for (state, words) in engine {
            let status = SessionStatus.engine(state)
            XCTAssertEqual(status.words, words)
            XCTAssertEqual(status.symbol, "memorychip")
            XCTAssertEqual(status.accessibilityLabel, "Model \(words)")
        }
        XCTAssertEqual(SessionStatus.engine(.loading(fraction: 1.2)).words, "Loading 100%")
        XCTAssertEqual(SessionStatus.pipe(.direct).accessibilityLabel, "Connection Direct")
        XCTAssertEqual(SessionStatus.pipe(.closed).words, "Reconnect")
        XCTAssertEqual(SessionStatus.pipe(.closed).symbol, "antenna.radiowaves.left.and.right.slash")
        let tinted = [SessionStatus.pipe(.closed), .engine(.failed)]
        for status in [SessionStatus.pipe(.idle), .pipe(.direct), .pipe(.closed)] + engine.map({ .engine($0.0) }) {
            XCTAssertEqual(status.asksToBePressed, tinted.contains(status), "\(status.words) is tinted wrongly")
        }
        XCTAssertTrue(SessionStatus.pipe(.idle).isUnderWay)
        XCTAssertTrue(SessionStatus.engine(.loading(fraction: 0)).isUnderWay)
        XCTAssertFalse(SessionStatus.engine(.ready).isUnderWay)
    }

    /// A server by address has no pill, and nor has This iPhone in a build
    /// that runs no model; a model the engine holds that is not the
    /// conversation's reads as not loaded.
    func testOnlyASessionThatCanRunHasAPill() async throws {
        let none = makeModel(engine: UnavailableEngine(), registry: LoopbackProviderRegistry())
        let server = ProviderConfig(name: "desk", kind: .openAICompatible(baseURL: AppModel.mockBaseURL))
        try none.addProvider(server, credentials: [:])
        XCTAssertNil(none.sessionStatus(for: none.newConversation(with: server)))
        let unrun = try none.addThisIPhone(defaultModel: MockEngine.model.id)
        XCTAssertNil(none.sessionStatus(for: none.newConversation(with: unrun)))

        let registry = LoopbackProviderRegistry()
        let model = makeModel(engine: MockEngine(registry: registry), registry: registry)
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        let other = model.newConversation(with: config)
        model.select(model: "another-model", for: other.id)
        let conversation = model.newConversation(with: config)
        await model.open(config).value
        try await XCTUnwrap(model.send("hi")).value
        let ready = await waitUntil { model.sessionStatus(for: conversation) == .engine(.ready) }
        XCTAssertTrue(ready, "the pill did not say the model was ready")
        let another = try XCTUnwrap(model.conversations.first { $0.id == other.id })
        XCTAssertEqual(model.sessionStatus(for: another), .engine(.notLoaded))
    }

    /// The engine refuses the conversation's model as too big: the pill says
    /// so, and pressing it opens the model browser. Another model reads as
    /// not loaded, and the engine served afresh, with the memory read again,
    /// forgets the refusal.
    func testATooBigModelSaysSoAndThePillOpensTheBrowser() async throws {
        let registry = LoopbackProviderRegistry()
        let model = makeModel(engine: MockEngine(behaviour: .tooBig, registry: registry), registry: registry)
        let config = try model.addThisIPhone(defaultModel: MockEngine.model.id)
        let conversation = model.newConversation(with: config)
        await model.open(config).value
        XCTAssertEqual(model.sessionStatus(for: conversation), .engine(.notLoaded))
        try await XCTUnwrap(model.send("hi")).value
        XCTAssertEqual(model.sessionStatus(for: conversation), .engine(.tooBig))

        XCTAssertTrue(model.offersPress(on: .engine(.tooBig), in: conversation))
        XCTAssertNil(model.onDevice.modelBrowser)
        model.press(.engine(.tooBig), in: conversation)
        XCTAssertNotNil(model.onDevice.modelBrowser, "Too big did not open the model browser")

        model.select(model: "a-smaller-model", for: conversation.id)
        let smaller = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(model.sessionStatus(for: smaller), .engine(.notLoaded))
        model.select(model: MockEngine.model.id, for: conversation.id)
        await model.shutDownEngine()
        await model.serveEngine()
        XCTAssertEqual(model.sessionStatus(for: try XCTUnwrap(model.selectedConversation)), .engine(.notLoaded))
    }

    /// Waits until `done` holds, on a clock, for
    /// `AppModelEngineTests.waitUntil`'s reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }
}
