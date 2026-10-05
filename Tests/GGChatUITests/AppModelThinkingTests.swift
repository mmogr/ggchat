import GGChatCore
import XCTest

@testable import GGChatUI

/// A conversation kept here can turn its model's thinking off: a setting of
/// the conversation, sent with every request it makes as a budget of zero,
/// to gglib alone, and offered only for a model gglib lists as one that
/// thinks (ADR 0009). With the switch on, a request is the one it always was.
final class AppModelThinkingTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    /// A gglib added by address, answered by `server` over
    /// `chat/completions`, its models listed, and a conversation open on the
    /// one that thinks.
    @MainActor
    private func makeGglib(_ server: any Provider) async throws -> (AppModel, ProviderConfig) {
        let (model, config) = try await Runs.makeModel(behind: server, direct: true)
        model.modelsByProvider[config.id] = MockProvider.sampleModels
        return (model, config)
    }

    private func answering(_ text: String = "fine") -> MockProvider {
        MockProvider(scripts: [.init(text: text)])
    }

    /// Send, Continue, a send that is refused and its Retry all build their
    /// request in one place, so each carries the budget, and so does a run's
    /// `PUT` sent again after its answer was lost, as the same body. Turned
    /// back on, the next request says nothing.
    @MainActor
    func testOffIsSentOnSendContinueRetryAndARunsPut() async throws {
        let recorder = RecordingProvider(wrapping: HangingProvider())
        let (model, _) = try await makeGglib(recorder)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.setThinking(off: true, for: id)

        let hanging = try XCTUnwrap(model.send("go"))
        try await Runs.until("the reply to start") { model.liveReply?.content == "half " }
        model.stop()
        await hanging.value
        recorder.wrap(answering("done"))
        try await XCTUnwrap(model.continueReply()).value
        let refusal = ProviderError.server(status: 503, code: "upstream_timeout", message: "busy")
        recorder.wrap(MockProvider(scripts: [.init(text: "")], failure: refusal))
        try await XCTUnwrap(model.send("and now?")).value
        recorder.wrap(answering("yes"))
        try await XCTUnwrap(model.retry()).value
        XCTAssertEqual(
            recorder.requests.map(\.reasoningBudgetTokens), [0, 0, 0, 0], "send, Continue, a refused send, Retry")
        XCTAssertEqual(recorder.requests.map(\.returnProgress), [true, true, true, true])

        model.setThinking(off: false, for: id)
        try await XCTUnwrap(model.send("and thinking again?")).value
        XCTAssertEqual(recorder.requests.count, 5)
        XCTAssertEqual(recorder.requests.map(\.reasoningBudgetTokens).last, .some(nil), "On still sent a budget")

        let hub = FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
        hub.with { $0.putsLost = 1 }
        let (piped, home) = try await Runs.makeModel(behind: hub, sleeper: ReadOnSleeper(immediate: true))
        piped.modelsByProvider[home.id] = MockProvider.sampleModels
        piped.setThinking(off: true, for: try XCTUnwrap(piped.selectedConversationID))
        try await XCTUnwrap(piped.send("go")).value
        try await Runs.until("the reply to be read on") { Runs.settled(piped) }
        let puts = hub.with { $0.starts.map(\.request) }
        XCTAssertEqual(puts.count, 2, "the lost PUT was not sent again")
        XCTAssertEqual(puts.map(\.reasoningBudgetTokens), [0, 0], "a run's PUT, and the PUT sent again")
        XCTAssertEqual(puts.first, puts.last, "the PUT sent again was another body")
    }

    /// With the switch on, gglib is sent the request it always was, with no
    /// budget under any value. A server not known to be gglib is never sent
    /// one, whatever the conversation stores and whatever its list says of
    /// the model, and is offered no switch.
    @MainActor
    func testOnSendsNoKeyAndAServerThatIsNotGglibNeverSeesIt() async throws {
        let recorder = RecordingProvider(wrapping: answering())
        let (model, _) = try await makeGglib(recorder)
        let id = try XCTUnwrap(model.selectedConversationID)
        XCTAssertEqual(model.selectedConversation?.thinkingOff, false, "a new conversation starts switched off")
        try await XCTUnwrap(model.send("hi")).value
        model.setThinking(off: true, for: id)
        model.setThinking(off: false, for: id)
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(recorder.requests.count, 2)
        for sent in recorder.requests {
            XCTAssertNil(sent.reasoningBudgetTokens)
            XCTAssertEqual(sent, ChatRequest(model: "mock-27b", messages: sent.messages, returnProgress: true))
        }

        let other = RecordingProvider(wrapping: answering())
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49997/v1"))
        model.registry.register(other, at: url)
        let server = ProviderConfig(name: "server", kind: .openAICompatible(baseURL: url), defaultModel: "mock-27b")
        try model.addProvider(server, credentials: [:])
        model.modelsByProvider[server.id] = MockProvider.sampleModels
        var conversation = model.newConversation()
        conversation.providerID = server.id
        conversation.thinkingOff = true
        model.update(conversation)
        XCTAssertFalse(model.offersThinking(for: conversation), "another server was offered the switch")
        try await XCTUnwrap(model.send("hi")).value
        let plain = try XCTUnwrap(other.requests.first)
        XCTAssertNil(plain.reasoningBudgetTokens, "a server not known to be gglib was sent the budget")
        XCTAssertEqual(plain, ChatRequest(model: "mock-27b", messages: plain.messages))
    }

    /// A stored Off is not sent to a model gglib's list names as one that
    /// does not think. A model the list does not name, and a list not read
    /// yet, as after a relaunch, are not known either way and are sent it:
    /// gglib takes the budget for any model.
    @MainActor
    func testAModelTheListNamesAsNotThinkingIsNotSentTheBudget() async throws {
        let recorder = RecordingProvider(wrapping: answering())
        let (model, config) = try await makeGglib(recorder)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.setThinking(off: true, for: id)
        let lists: [([ModelInfo], Int?)] = [
            ([], 0),
            ([ModelInfo(id: "mock-27b")], nil),
            ([ModelInfo(id: "mock-27b", capabilities: ["vision"])], nil),
            ([ModelInfo(id: "another", capabilities: ["reasoning"])], 0),
            (MockProvider.sampleModels, 0),
        ]
        for (list, budget) in lists {
            model.modelsByProvider[config.id] = list
            try await XCTUnwrap(model.send("hi")).value
            XCTAssertEqual(recorder.requests.map(\.reasoningBudgetTokens).last, .some(budget), "\(list)")
        }
        XCTAssertEqual(recorder.requests.count, lists.count)
    }

    /// The choice is written through the store, leaves the conversation
    /// where it was in the list, and is read back by the next launch, which
    /// sends it with its first request. Turned back on, the launch after
    /// that reads it on.
    @MainActor
    func testTheChoiceSurvivesARelaunch() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let secrets = InMemorySecrets()
        var tick = 1_700_000_000.0
        func launch(far: any Provider) -> AppModel {
            let registry = LoopbackProviderRegistry()
            let defaults = UserDefaults(suiteName: "AppModelThinkingTests.\(UUID().uuidString)")!
            return AppModel(
                store: store, secrets: secrets, log: NoopLogSink(), registry: registry,
                pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), provider: far, registry: registry),
                diagnostics: Diagnostics(defaults: defaults),
                now: {
                    tick += 60
                    return Date(timeIntervalSince1970: tick)
                })
        }
        let first = launch(far: MockProvider())
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(Runs.ticket)), defaultModel: "mock-27b")
        try first.addProvider(config, credentials: [.ticket: Runs.ticket, .token: "secret-token"])
        let conversation = first.newConversation()
        first.setThinking(off: true, for: conversation.id)
        XCTAssertEqual(first.selectedConversation?.thinkingOff, true)
        XCTAssertEqual(
            first.selectedConversation?.updatedAt, conversation.updatedAt, "a setting moved the conversation up")

        let recorder = RecordingProvider(wrapping: answering())
        let reloaded = launch(far: recorder)
        reloaded.load()
        XCTAssertEqual(reloaded.selectedConversationID, conversation.id)
        XCTAssertEqual(reloaded.selectedConversation?.thinkingOff, true, "the switch flipped back after a relaunch")
        try await Runs.until("the launch's dial") { reloaded.pipeStatus(for: config.id) == .direct }
        try await XCTUnwrap(reloaded.send("hi")).value
        XCTAssertEqual(recorder.requests.map(\.reasoningBudgetTokens), [0])

        reloaded.setThinking(off: false, for: conversation.id)
        let again = launch(far: recorder)
        again.load()
        XCTAssertEqual(again.selectedConversation?.thinkingOff, false, "turning it back on was not kept")
    }

    /// Picking a model the list names as one that does not think clears a
    /// stored Off: there is no switch left to turn it back on with, and
    /// picking the first model again must not send it. Another model that
    /// thinks keeps the choice, and so does one the list does not name.
    @MainActor
    func testPickingAModelThatDoesNotThinkClearsTheChoice() async throws {
        let recorder = RecordingProvider(wrapping: answering())
        let (model, config) = try await makeGglib(recorder)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.modelsByProvider[config.id] =
            MockProvider.sampleModels + [ModelInfo(id: "mock-9b", capabilities: ["vision", "reasoning"])]
        func off() -> Bool? { model.selectedConversation?.thinkingOff }
        model.setThinking(off: true, for: id)
        model.select(model: "mock-9b", for: id)
        XCTAssertEqual(off(), true, "another model that thinks lost the choice")
        model.select(model: "not-listed", for: id)
        XCTAssertEqual(off(), true, "a model the list does not name lost the choice")

        model.select(model: "mock-4b", for: id)
        XCTAssertEqual(off(), false, "a stored Off outlived its switch")
        XCTAssertFalse(model.offersThinking(for: try XCTUnwrap(model.selectedConversation)))
        model.select(model: "mock-27b", for: id)
        XCTAssertEqual(off(), false, "the switch came back off")
        XCTAssertTrue(model.offersThinking(for: try XCTUnwrap(model.selectedConversation)))
        try await XCTUnwrap(model.send("hi")).value
        XCTAssertEqual(recorder.requests.map(\.reasoningBudgetTokens), [nil], "a cleared Off was sent")
    }

    /// The switch is offered only where it can do something: the provider is
    /// gglib, a pipe or a server that answered the status probe, and its
    /// list names the conversation's model, or the provider's default when
    /// it has none of its own, as one that thinks. A model that does not
    /// think, one the list does not name, a list not read, an older gglib
    /// that lists no `reasoning`, another server and no provider at all
    /// offer none.
    @MainActor
    func testTheSwitchIsOfferedOnlyForAGglibModelListedAsThinking() async throws {
        let (model, config) = try await makeGglib(answering())
        var conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(model.offersThinking(for: conversation))
        conversation.model = nil
        XCTAssertTrue(model.offersThinking(for: conversation), "the provider's default model was not looked up")
        for other in ["mock-4b", "not-listed"] {
            conversation.model = other
            XCTAssertFalse(model.offersThinking(for: conversation), other)
        }
        conversation.model = "mock-27b"
        let older = [ModelInfo(id: "mock-27b"), ModelInfo(id: "mock-4b", capabilities: ["vision"])]
        for list in [[], older] {
            model.modelsByProvider[config.id] = list
            XCTAssertFalse(model.offersThinking(for: conversation), "\(list)")
        }
        model.modelsByProvider[config.id] = MockProvider.sampleModels
        XCTAssertTrue(model.offersThinking(for: conversation))

        model.proxyStatusAvailability[config.id] = false
        XCTAssertFalse(model.offersThinking(for: conversation), "a server that is not gglib was offered the switch")
        model.proxyStatusAvailability[config.id] = nil
        XCTAssertFalse(model.offersThinking(for: conversation), "a server not probed yet was offered the switch")
        conversation.providerID = UUID()
        XCTAssertFalse(model.offersThinking(for: conversation), "a conversation with no provider was offered it")

        let (piped, home) = try await Runs.makeModel(behind: answering())
        let own = try XCTUnwrap(piped.selectedConversation)
        XCTAssertFalse(piped.offersThinking(for: own), "a pipe whose models were never listed was offered it")
        piped.modelsByProvider[home.id] = MockProvider.sampleModels
        XCTAssertTrue(piped.offersThinking(for: own), "a pipe is gglib, and its model thinks")
    }

    /// What the top bar's switch is handed and what a press on it sets, each
    /// the opposite of off and taken in the model: a new conversation's
    /// switch shows on, a press to off is kept as off and sends the budget,
    /// and a press to on sends none.
    @MainActor
    func testTheSwitchShowsOnUnlessOffAndAPressSetsWhatItShows() async throws {
        let recorder = RecordingProvider(wrapping: answering())
        let (model, _) = try await makeGglib(recorder)
        let id = try XCTUnwrap(model.selectedConversationID)
        func shownOn() throws -> Bool { model.thinkingOn(for: try XCTUnwrap(model.selectedConversation)) }
        XCTAssertTrue(try shownOn(), "a new conversation's switch showed off")
        model.setThinking(on: false, for: id)
        XCTAssertFalse(try shownOn(), "a press to off did not show off")
        XCTAssertEqual(model.selectedConversation?.thinkingOff, true)
        try await XCTUnwrap(model.send("hi")).value
        model.setThinking(on: true, for: id)
        XCTAssertTrue(try shownOn(), "a press to on did not show on")
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(recorder.requests.map(\.reasoningBudgetTokens), [0, nil])
    }

    /// The switch's state is a symbol and a spoken word, each different on
    /// and off, and never the tint alone.
    @MainActor
    func testTheSwitchSaysItsStateWithASymbolAndAWord() {
        XCTAssertEqual(ThinkingToggle.symbol(isOn: true), "brain.fill")
        XCTAssertEqual(ThinkingToggle.symbol(isOn: false), "brain")
        XCTAssertEqual(ThinkingToggle.value(isOn: true), "On")
        XCTAssertEqual(ThinkingToggle.value(isOn: false), "Off")
    }
}
