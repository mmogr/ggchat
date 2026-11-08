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

    /// A chat saved with a model the list no longer names, as one saved by
    /// its name before chats were keyed or one whose model was deleted,
    /// runs on the provider's default and is shown under the default's name.
    /// Until the list is read the chat's own model is taken at its word, and
    /// on a list that names its models by name, not gglib's ids, always.
    func testAChatWhoseModelIsNotListedRunsOnTheDefault() async throws {
        let recorder = RecordingProvider(
            wrapping: listing([ModelInfo(id: "Qwen3.8 27B", gglibID: 3), ModelInfo(id: "Plain", gglibID: 2)]))
        let (model, config) = try await Runs.makeModel(behind: recorder, direct: true)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.select(model: "Qwen3.8-27B", for: id)
        XCTAssertEqual(model.model(for: try XCTUnwrap(model.selectedConversation)), "Qwen3.8-27B")

        await model.refreshModels(for: config)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(conversation.model, "Qwen3.8-27B", "the old name was rewritten rather than passed over")
        XCTAssertEqual(model.model(for: conversation), "3")
        XCTAssertEqual(model.shownModelName(for: conversation), "Qwen3.8 27B")
        try await XCTUnwrap(model.send("go")).value
        XCTAssertEqual(try sentModel(recorder.requests.last), "3", "the unlisted name was sent")
        XCTAssertNil(model.streamErrors[id])

        model.select(model: "2", for: id)
        let listed = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(model.model(for: listed), "2", "a listed model was passed over")

        recorder.wrap(listing([ModelInfo(id: "Plain")]))
        await model.refreshModels(for: config)
        model.select(model: "Qwen3.8-27B", for: id)
        try await XCTUnwrap(model.send("by name")).value
        XCTAssertEqual(try sentModel(recorder.requests.last), "Qwen3.8-27B", "a list by name sent the default")
    }

    /// A list that no longer names the provider's default replaces it with
    /// the first model that chats, and one that names it keeps it, so the
    /// default a chat falls back on is always one the list names. A list
    /// that names its models by name, not gglib's ids, keeps the default as
    /// it was.
    func testADefaultTheListNoLongerNamesIsReplaced() async throws {
        let recorder = RecordingProvider(
            wrapping: listing([
                ModelInfo(id: "Drawer", gglibID: 5, capabilities: ["image_generation"]),
                ModelInfo(id: "First", gglibID: 1), ModelInfo(id: "Second", gglibID: 2),
            ]))
        let (model, config) = try await Runs.makeModel(behind: recorder, direct: true)
        XCTAssertEqual(model.providers.first?.defaultModel, "mock-27b")
        await model.refreshModels(for: config)
        XCTAssertEqual(model.providers.first?.defaultModel, "1", "the default the list does not name was kept")

        var chosen = try XCTUnwrap(model.providers.first)
        chosen.defaultModel = "2"
        model.updateProvider(chosen)
        await model.refreshModels(for: config)
        XCTAssertEqual(model.providers.first?.defaultModel, "2", "a default the list names was replaced")

        recorder.wrap(listing([ModelInfo(id: "First", gglibID: 1)]))
        await model.refreshModels(for: config)
        XCTAssertEqual(model.providers.first?.defaultModel, "1", "a deleted default was kept")

        recorder.wrap(listing([ModelInfo(id: "Other")]))
        await model.refreshModels(for: config)
        XCTAssertEqual(model.providers.first?.defaultModel, "1", "a list that names models by name replaced it")
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
