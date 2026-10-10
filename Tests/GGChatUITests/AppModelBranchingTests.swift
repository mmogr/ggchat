import GGChatCore
import XCTest

@testable import GGChatUI

/// Edit, regenerate and Branch from here on this device's conversations
/// (ADR 0010): a change that would discard or alter a saved reply is made on
/// a new branch, which opens and is answered there, and the conversation it
/// was made on is left as it was.
final class AppModelBranchingTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:49994/v1")!

    @MainActor
    private func makeModel(_ provider: any Provider) throws -> AppModel {
        let registry = LoopbackProviderRegistry()
        registry.register(provider, at: baseURL)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addProvider(
            ProviderConfig(name: "mock", kind: .openAICompatible(baseURL: baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        return model
    }

    /// A model whose open conversation asked one question and was answered.
    @MainActor
    private func answered(_ recorder: RecordingProvider) async throws -> (AppModel, Conversation) {
        let model = try makeModel(recorder)
        try await XCTUnwrap(model.send("Plan a trip to Kyoto")).value
        return (model, try XCTUnwrap(model.selectedConversation))
    }

    @MainActor
    func testAnEditOfAnAnsweredQuestionOpensABranchAnsweredThere() async throws {
        let recorder = RecordingProvider(
            wrapping: MockProvider(scripts: [.init(text: "Day 1: temples"), .init(text: "One day: Fushimi Inari")]))
        let (model, original) = try await answered(recorder)

        try await XCTUnwrap(model.edit(original.messages[0].id, in: original.id, to: "Plan a short trip")).value

        let branch = try XCTUnwrap(model.selectedConversation)
        XCTAssertNotEqual(branch.id, original.id)
        XCTAssertEqual(branch.branchOf, original.id)
        XCTAssertEqual(branch.messages.map(\.content), ["Plan a short trip", "One day: Fushimi Inari"])
        XCTAssertEqual(recorder.requests.last?.messages.map(\.content), ["Plan a short trip"])
        let kept = try XCTUnwrap(model.conversations.first { $0.id == original.id })
        XCTAssertEqual(kept.messages, original.messages, "the conversation the edit was made on changed")
    }

    @MainActor
    func testAnEditOfTheLastQuestionNothingAnswersIsMadeInPlace() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Day 1: gardens")]))
        let model = try makeModel(recorder)
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages = [Message(role: .user, content: "Plan a trip", createdAt: .distantPast)]
        model.update(conversation)

        try await XCTUnwrap(model.edit(conversation.messages[0].id, in: conversation.id, to: "Plan a long trip")).value

        XCTAssertEqual(model.conversations.count, 1, "an unanswered question's edit made a branch")
        let edited = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(edited.id, conversation.id)
        XCTAssertEqual(edited.messages.map(\.content), ["Plan a long trip", "Day 1: gardens"])
    }

    @MainActor
    func testARegenerateBranchesAndBothConversationsOfferEitherReply() async throws {
        // The mock answers by the request's length, so the first reply is
        // written here to tell the two apart, and dated before the model's
        // clock, which stands still, so it is the older.
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Day 1: markets")]))
        let (model, answeredOriginal) = try await answered(recorder)
        var original = answeredOriginal
        original.messages[1].content = "Day 1: temples"
        original.messages[1].createdAt = .distantPast
        model.update(original)

        try await XCTUnwrap(model.regenerate(original.messages[1].id, in: original.id)).value

        let branch = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(branch.messages.map(\.content), ["Plan a trip to Kyoto", "Day 1: markets"])
        XCTAssertEqual(branch.messages[0].originID, original.messages[0].id)
        for conversation in [branch, try XCTUnwrap(model.conversations.first { $0.id == original.id })] {
            let points = model.branchPoints(of: conversation)
            XCTAssertEqual(points.count, 1)
            XCTAssertEqual(points.first?.messageID, conversation.messages[1].id)
            XCTAssertEqual(
                points.first?.options.map(\.preview), ["Day 1: temples", "Day 1: markets"], "not oldest first")
        }
        model.openBranch(original.id)
        XCTAssertEqual(model.selectedConversationID, original.id)
    }

    @MainActor
    func testAnEditedReplyIsKeptAsWrittenOnABranchAndNotAnswered() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Day 1: temples")]))
        let (model, original) = try await answered(recorder)

        XCTAssertNil(model.edit(original.messages[1].id, in: original.id, to: "Day 1: tea houses"))

        let branch = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(branch.messages.map(\.content), ["Plan a trip to Kyoto", "Day 1: tea houses"])
        XCTAssertEqual(branch.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(recorder.requests.count, 1, "an edited reply was answered")
    }

    @MainActor
    func testBranchFromHereCopiesTheConversationAndSendsNothing() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Day 1: temples")]))
        let (model, original) = try await answered(recorder)

        model.branch(from: original.messages[0].id, in: original.id)

        let branch = try XCTUnwrap(model.selectedConversation)
        XCTAssertNotEqual(branch.id, original.id)
        XCTAssertEqual(branch.messages.map(\.content), ["Plan a trip to Kyoto"])
        XCTAssertEqual(branch.family, original.id)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    @MainActor
    func testAReplySavedAsItWasIsRefusedAndMakesNoBranch() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Day 1: temples")]))
        let (model, answeredOriginal) = try await answered(recorder)
        var original = answeredOriginal
        original.messages[1].content = "Day 1: temples\n"
        model.update(original)

        XCTAssertNil(model.edit(original.messages[1].id, in: original.id, to: "Day 1: temples"))

        XCTAssertEqual(model.conversations.count, 1, "a reply saved as it was made a branch")
        XCTAssertNil(model.lastError)
    }

    /// While its reply streams, the last question is no longer edited in
    /// place: the edit is made on a branch, and the question the reply
    /// answers is left as it was.
    @MainActor
    func testAQuestionWhoseReplyIsStreamingIsEditedOnABranch() async throws {
        let model = try makeModel(HangingProvider())
        let streaming = try XCTUnwrap(model.send("Plan a trip"))
        let original = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(model.isStreaming(original.id))

        model.edit(original.messages[0].id, in: original.id, to: "Plan a long trip")

        XCTAssertEqual(model.conversations.count, 2, "the question was edited under its streaming reply")
        let kept = try XCTUnwrap(model.conversations.first { $0.id == original.id })
        XCTAssertEqual(kept.messages.map(\.content), ["Plan a trip"])
        model.stop()
        await streaming.value
    }

    @MainActor
    func testARegenerateOfAQuestionIsRefusedAndChangesNothing() async throws {
        let recorder = RecordingProvider(wrapping: MockProvider(scripts: [.init(text: "Day 1: temples")]))
        let (model, original) = try await answered(recorder)

        XCTAssertNil(model.regenerate(original.messages[0].id, in: original.id))

        XCTAssertEqual(model.lastError, "Only a reply can be answered again.")
        XCTAssertEqual(model.conversations.count, 1)
    }
}
