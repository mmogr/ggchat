import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// Streams the events it was given and ends: a reply that finishes the way a
/// test says, which `MockProvider`, always ending in `stop`, cannot.
private struct EndingProvider: Provider {
    let events: [ChatEvent]

    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// The context reading of a conversation kept on this phone: left by a reply
/// that finished, on the chat route and on a run, kept with the conversation,
/// and drawn only under the model that made it.
@MainActor
final class AppModelContextTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private static let baseURL = URL(string: "http://127.0.0.1:49993/v1")!
    private let english = Locale(identifier: "en_US")
    /// Five words, so the mock says five tokens were written.
    private let script = MockProvider.Script(text: "It is a short answer.")
    private let counted = Usage(promptTokens: 8_000, completionTokens: 200, contextSize: 32_768, trimmedMessages: 3)

    /// A model on a server added by address and not known to be gglib, so
    /// its replies go the chat route.
    private func makeModel(
        _ provider: any Provider, store: any Store = InMemoryStore()
    ) throws -> (AppModel, LoopbackProviderRegistry) {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: Self.baseURL)
        let model = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addProvider(
            ProviderConfig(name: "mock", kind: .openAICompatible(baseURL: Self.baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        return (model, registry)
    }

    /// A gglib whose runs write a few words and then report `counts`, each
    /// in a frame of its own.
    private func hub(_ counts: ChatEvent...) -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning) + counts.map { [$0] })
    }

    private func kept(_ model: AppModel) -> ContextReading? {
        model.selectedConversation?.context
    }

    private func shown(_ model: AppModel) throws -> ContextReading? {
        model.contextReading(for: try XCTUnwrap(model.selectedConversation))
    }

    /// A reply that finishes leaves what its call counted: the prompt and the
    /// completion of that call, under the model that was asked. The next
    /// reply's takes its place and nothing is added up. On a run the counts
    /// come in a frame of their own, and the last call's are the reply's. It
    /// is kept with the conversation, so a relaunch draws it.
    func testAFinishedReplyKeepsItsReadingOnBothRoutes() async throws {
        let store = InMemoryStore()
        let (model, _) = try makeModel(MockProvider(scripts: [script]), store: store)
        XCTAssertNil(try shown(model), "a conversation with no reply has a reading")
        try await XCTUnwrap(model.send("go")).value
        let first = try XCTUnwrap(kept(model))
        XCTAssertEqual(
            first, ContextReading(promptTokens: 1, completionTokens: 5, contextSize: 4_096, model: "mock-27b"))
        XCTAssertEqual(first.used, 6, "used is what the call read and what it wrote")
        XCTAssertEqual(try shown(model), first)

        try await XCTUnwrap(model.send("and again")).value
        let second = try XCTUnwrap(kept(model))
        XCTAssertEqual(second.used, 13, "the newest call's counts, eight read and five written, not a sum")
        let relaunched = AppModel(
            store: store, secrets: InMemorySecrets(), log: NoopLogSink(), registry: LoopbackProviderRegistry())
        relaunched.load()
        XCTAssertEqual(kept(relaunched), second)
        XCTAssertEqual(try shown(relaunched), second)

        let earlier = Usage(promptTokens: 500, completionTokens: 40, contextSize: 32_768)
        for direct in [false, true] {
            let hub = hub(.usage(earlier, reason: "tool_calls"), .usage(counted, reason: "stop"))
            let (onRuns, _) = try await Runs.makeModel(behind: hub, direct: direct)
            try await XCTUnwrap(onRuns.send("go")).value
            XCTAssertEqual(try Runs.last(onRuns).content, Runs.text)
            XCTAssertEqual(hub.with { $0.chats.count }, 0, "the reply did not go as a run")
            let reading = try XCTUnwrap(kept(onRuns))
            XCTAssertEqual(reading, ContextReading(counted, reason: "stop", model: "mock-27b"))
            XCTAssertEqual(reading.used, 8_200, "the last call's counts, not a sum")
            XCTAssertEqual(
                reading.lines(in: english),
                [
                    "8,200 of 32,768 tokens (25%) after the last finished reply.",
                    "3 earlier messages were shortened or left out to fit.",
                ])
            XCTAssertEqual(try shown(onRuns), reading)
        }
    }

    /// A reply that fails, drops or is stopped leaves the reading as it was,
    /// with its call's counts in hand or without them, and so does walking
    /// away from a run. A reply that finishes with no size reported leaves
    /// none: no older reading in its place, and never the size the model
    /// list gives.
    func testAStoppedOrFailedReplyLeavesTheReadingAndAFinishedOneWithoutASizeClearsIt() async throws {
        let (model, registry) = try makeModel(MockProvider(scripts: [script]))
        let config = try XCTUnwrap(model.providers.first)
        await model.refreshModels(for: config)
        XCTAssertEqual(model.models(for: config.id).first?.contextWindow, 131_072, "the list gives a size")
        try await XCTUnwrap(model.send("go")).value
        let reading = try XCTUnwrap(kept(model))

        let refused = ProviderError.server(status: 500, code: "upstream_error", message: "gone")
        let dropping = MockProvider(scripts: [script], failAfterTokens: 2)
        for broken in [dropping, MockProvider(scripts: [script], failure: refused)] {
            registry.register(broken, at: Self.baseURL)
            try await XCTUnwrap(model.send("more")).value
            XCTAssertNotNil(try Runs.last(model).failure)
            XCTAssertEqual(kept(model), reading, "a failed reply moved the reading")
        }
        registry.register(
            MockProvider(scripts: [script], sleeper: ContinuousClockSleeper(), tokenDelay: .seconds(30)),
            at: Self.baseURL)
        let stopped = try XCTUnwrap(model.send("slowly"))
        model.stop()
        await stopped.value
        XCTAssertEqual(kept(model), reading, "a stopped reply moved the reading")

        registry.register(MockProvider(scripts: [script], contextSize: nil), at: Self.baseURL)
        try await XCTUnwrap(model.send("last")).value
        XCTAssertFalse(try Runs.last(model).isPartial)
        XCTAssertNil(kept(model), "a reply with no size reported left a reading")
        XCTAssertNil(try shown(model))

        // On a run the counts can be in hand when the reply does not finish.
        let hub = hub(.usage(counted, reason: "stop"))
        let (onRuns, _) = try await Runs.makeModel(behind: hub)
        try await XCTUnwrap(onRuns.send("go")).value
        let before = try XCTUnwrap(kept(onRuns))
        let frames = hub.with { state -> UInt32 in
            let moved = Usage(promptTokens: 30_000, completionTokens: 900, contextSize: 32_768)
            state.frames[state.frames.count - 1] = [.usage(moved, reason: "stop")]
            state.ending = .failed
            state.error = RunError(code: "upstream_error", message: "it broke")
            return UInt32(state.frames.count)
        }
        try await XCTUnwrap(onRuns.send("again")).value
        XCTAssertNotNil(try Runs.last(onRuns).failure)
        XCTAssertEqual(kept(onRuns), before, "a failed run moved the reading")

        for backgrounds in [false, true] {
            hub.with {
                $0.ending = .completed
                $0.error = nil
                $0.holdAt = frames
            }
            let task = try XCTUnwrap(onRuns.send("once more"))
            try await Runs.until("the counts") { onRuns.liveReply?.cursor == frames }
            XCTAssertNotNil(onRuns.liveReply?.usage)
            if backgrounds { await onRuns.scene(.background).value } else { onRuns.stop() }
            await task.value
            XCTAssertEqual(kept(onRuns), before, backgrounds ? "walking away moved it" : "Stop moved it")
        }
    }

    /// A reading says what the model that made it will find, so under
    /// another model it is not drawn, and back on the same model it is. A
    /// conversation that names no model follows its provider's default.
    func testAnotherModelHidesTheReadingAndTheSameModelShowsItAgain() async throws {
        let (model, _) = try makeModel(MockProvider(scripts: [script]))
        try await XCTUnwrap(model.send("go")).value
        let id = try XCTUnwrap(model.selectedConversationID)
        let reading = try XCTUnwrap(try shown(model))
        XCTAssertEqual(reading.model, "mock-27b")

        model.select(model: "mock-4b", for: id)
        XCTAssertNil(try shown(model), "another model's reading was drawn")
        XCTAssertEqual(kept(model), reading, "the reading was thrown away")
        model.select(model: "mock-27b", for: id)
        XCTAssertEqual(try shown(model), reading)

        var unnamed = try XCTUnwrap(model.selectedConversation)
        unnamed.model = nil
        model.update(unnamed)
        XCTAssertEqual(try shown(model), reading, "the provider's default is the model that made it")
        var config = try XCTUnwrap(model.providers.first)
        config.defaultModel = "mock-4b"
        model.updateProvider(config)
        XCTAssertNil(try shown(model), "a changed default drew another model's reading")
        config.defaultModel = "mock-27b"
        model.updateProvider(config)
        XCTAssertEqual(try shown(model), reading)

        model.select(model: "mock-4b", for: id)
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(try shown(model)?.model, "mock-4b", "a reply under the other model left no reading of its own")
    }

    /// A reply walked away from and read on leaves its reading when the run
    /// ends, under the model the run's report names: a conversation moved to
    /// another model while the hub wrote on does not draw it as its own. One
    /// walked away from after its counts arrived finishes with no reading
    /// (ADR 0008).
    func testReadingOnFromARunKeepsItsReading() async throws {
        let hub = hub(.usage(counted, reason: "stop"))
        hub.with {
            $0.holdAt = 2
            $0.reportsModel = "mock-27b"
        }
        let (model, _) = try await Runs.makeModel(behind: hub)
        let task = try XCTUnwrap(model.send("go"))
        try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
        await model.scene(.background).value
        await task.value
        XCTAssertNil(kept(model), "a reply still being written left a reading")

        let id = try XCTUnwrap(model.selectedConversationID)
        model.select(model: "mock-4b", for: id)
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
        XCTAssertEqual(hub.with { $0.reads.map(\.after) }, [0, 2])
        let reading = try XCTUnwrap(kept(model))
        XCTAssertEqual(reading, ContextReading(counted, reason: "stop", model: "mock-27b"))
        XCTAssertNil(try shown(model), "drawn under a model that did not make it")
        model.select(model: "mock-27b", for: id)
        XCTAssertEqual(try shown(model), reading)

        // Counts read just before walking away are not sent again, so that
        // reply finishes with no reading, and not with the one before it.
        let frames = hub.with { UInt32($0.frames.count) }
        hub.with { $0.holdAt = frames }
        let again = try XCTUnwrap(model.send("again"))
        try await Runs.until("the counts") { model.liveReply?.cursor == frames }
        await model.scene(.background).value
        await again.value
        XCTAssertEqual(kept(model), reading, "walking away moved the reading")
        hub.with { $0.holdAt = nil }
        await model.scene(.foreground).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        XCTAssertFalse(try Runs.last(model).isPartial)
        XCTAssertNil(kept(model), "a reply whose counts were not read again kept the reading before it")
    }

    /// A reply whose call ended at its length limit says so in the sheet, on
    /// the chat route and on a run, and one that ended any other way does
    /// not.
    func testAReplyCutOffSaysSo() async throws {
        let counts = "8,200 of 32,768 tokens (25%) after the last finished reply."
        let trim = "3 earlier messages were shortened or left out to fit."
        let cut = "The last reply was cut off before it finished."
        let (model, registry) = try makeModel(
            EndingProvider(events: [.delta("half an ans"), .finished(reason: "length", usage: counted)]))
        try await XCTUnwrap(model.send("go")).value
        XCTAssertFalse(try Runs.last(model).isPartial)
        XCTAssertEqual(try shown(model)?.lines(in: english), [counts, trim, cut])
        registry.register(
            EndingProvider(events: [.delta("a whole answer"), .finished(reason: "stop", usage: counted)]),
            at: Self.baseURL)
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(try shown(model)?.lines(in: english), [counts, trim], "the next reply was not cut off")

        for (reason, lines) in [("length", [counts, trim, cut]), ("stop", [counts, trim])] {
            let (onRuns, _) = try await Runs.makeModel(behind: hub(.usage(counted, reason: reason)))
            try await XCTUnwrap(onRuns.send("go")).value
            XCTAssertEqual(try shown(onRuns)?.lines(in: english), lines, reason)
        }
    }
}
