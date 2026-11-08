import Foundation
import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// A conversation names a gglib model by its key, the catalogue id (with
/// `:<profile>` for a profile variant), and shows the name the list gives
/// it now: a rename on the Mac changes the name shown and nothing else.
@MainActor
final class ModelKeyTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private let english = Locale(identifier: "en_US")
    private let calendar = Calendar(identifier: .gregorian)

    private func listing(_ models: [ModelInfo]) -> MockProvider {
        MockProvider(models: models, scripts: [.init(text: "fine")])
    }

    /// The model `body` was sent for, as the request's JSON says it.
    private func sentModel(_ request: ChatRequest?) throws -> String? {
        let body = try JSONEncoder().encode(ChatCompletionRequest(try XCTUnwrap(request)))
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return object?["model"] as? String
    }

    /// gglib lists id 1 as "A" and the chat picks it, then lists id 1 as
    /// "B". The pill, the chat's panel and the list of chats say "B", the
    /// request still names the model "1", the lookups that ask the list of
    /// the chat's model, Thinking and images, still find it, and the context
    /// ring is still drawn under it.
    func testARenameOnTheMacChangesOnlyTheNameShown() async throws {
        let seer = ["vision", "reasoning"]
        let recorder = RecordingProvider(
            wrapping: listing([
                ModelInfo(id: "A", gglibID: 1, capabilities: seer), ModelInfo(id: "Plain", gglibID: 2),
            ]))
        let (model, config) = try await Runs.makeModel(behind: recorder, direct: true)
        await model.refreshModels(for: config)
        let id = try XCTUnwrap(model.selectedConversationID)
        let sections = model.modelListSections(
            for: try XCTUnwrap(model.selectedConversation), locale: english, calendar: calendar)
        let rows = try XCTUnwrap(sections.first { $0.id == config.id }).rows
        XCTAssertEqual(rows.map(\.modelID), ["1", "2"])
        XCTAssertEqual(rows.map(\.name), ["A", "Plain"])
        model.pick(model: rows[0].modelID, on: config.id, for: id)
        XCTAssertEqual(model.selectedConversation?.model, "1", "the chat stored the name, not the id")
        try await XCTUnwrap(model.send("go")).value
        XCTAssertEqual(try sentModel(recorder.requests.last), "1")

        recorder.wrap(
            listing([ModelInfo(id: "B", gglibID: 1, capabilities: seer), ModelInfo(id: "Plain", gglibID: 2)]))
        await model.refreshModels(for: config)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(model.shownModelName(for: conversation), "B")
        XCTAssertEqual(model.name(of: conversation.model, on: config.id), "B")
        XCTAssertTrue(model.offersThinking(for: conversation), "the renamed model lost its Thinking switch")
        XCTAssertTrue(model.canSee(conversation), "the renamed model was taken for one that reads no images")
        XCTAssertEqual(model.contextReading(for: conversation)?.model, "1", "the ring went with the old name")
        let renamed = model.modelListSections(for: conversation, locale: english, calendar: calendar)
        let ticked = try XCTUnwrap(renamed.first { $0.id == config.id }).rows.filter(\.isCurrent)
        XCTAssertEqual(ticked.map(\.name), ["B"])
        try await XCTUnwrap(model.send("again")).value
        XCTAssertEqual(try sentModel(recorder.requests.last), "1", "the rename changed what was sent")
    }

    /// A profile variant shares its base model's id, so its key names the
    /// profile after it: the list offers both, a pick of the variant stores
    /// and sends `1:creative`, and it is shown by the variant's name.
    func testAProfileVariantIsKeyedByItsIdAndProfile() async throws {
        let recorder = RecordingProvider(
            wrapping: listing([
                ModelInfo(id: "A", gglibID: 1), ModelInfo(id: "A:creative", gglibID: 1, profile: "creative"),
            ]))
        let (model, config) = try await Runs.makeModel(behind: recorder, direct: true)
        await model.refreshModels(for: config)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.pick(model: "1:creative", on: config.id, for: id)
        let conversation = try XCTUnwrap(model.selectedConversation)
        let rows = try XCTUnwrap(
            model.modelListSections(for: conversation, locale: english, calendar: calendar)
                .first { $0.id == config.id }
        ).rows
        XCTAssertEqual(rows.map(\.modelID), ["1", "1:creative"])
        XCTAssertEqual(rows.filter(\.isCurrent).map(\.name), ["A:creative"])
        XCTAssertEqual(model.shownModelName(for: conversation), "A:creative")
        try await XCTUnwrap(model.send("go")).value
        XCTAssertEqual(try sentModel(recorder.requests.last), "1:creative")
    }

    /// This iPhone's list is kept by name: its library and its engine name
    /// a model by what it is installed as, so the id its own gglib lists is
    /// dropped when the list is read, and its default and the Thinking
    /// lookup still find the model by name. Any other provider's list is
    /// kept as it came.
    func testThisIPhonesModelsAreKeyedByName() async throws {
        let name = MockEngine.model.id
        let listed = [
            ModelInfo(id: name, gglibID: 4, capabilities: ["reasoning"]),
            ModelInfo(id: "\(name):fast", gglibID: 4, profile: "fast"),
        ]
        let registry = LoopbackProviderRegistry()
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            engine: MockEngine(registry: registry, provider: listing(listed)), library: MockLibrary(),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "ModelKeyTests.\(UUID().uuidString)")!),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let phone = try model.addThisIPhone(defaultModel: name)
        model.newConversation()
        await model.open(phone).value
        await model.refreshModels(for: phone)
        XCTAssertEqual(model.models(for: phone.id).map(\.key), [name, "\(name):fast"], "the phone kept gglib's ids")
        XCTAssertEqual(model.providers.first { $0.id == phone.id }?.defaultModel, name)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(model.offersThinking(for: conversation), "the phone's model was not found by name")

        let server = ProviderConfig(name: "home", kind: .openAICompatible(baseURL: MockEngine.baseURL))
        XCTAssertEqual(model.kept(listed, from: server).map(\.key), ["4", "4:fast"])
    }
}
