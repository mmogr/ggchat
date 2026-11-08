import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// A reply on a gglib run leaves its context reading under the key it was
/// sent, whatever name the run's report gives the model: gglib reports the
/// catalogue name a run went to, which is a profile variant's base name, and
/// the bare name of models that share one.
@MainActor
final class ModelKeyRunTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private let counted = Usage(promptTokens: 8_000, completionTokens: 200, contextSize: 32_768, trimmedMessages: 3)

    /// A gglib listing `models` whose runs write a few words, then report
    /// the counts, and end naming the model `report`.
    private func hub(listing models: [ModelInfo], reporting report: String) -> FakeRunHub {
        let hub = FakeRunHub(
            frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning) + [
                [.usage(counted, reason: "stop")]
            ])
        hub.with {
            $0.models = models
            $0.reportsModel = report
        }
        return hub
    }

    /// The model on `hub`, its list read, with its conversation on `key`.
    private func makeModel(behind hub: FakeRunHub, on key: String) async throws -> (AppModel, UUID) {
        let (model, config) = try await Runs.makeModel(behind: hub)
        await model.refreshModels(for: config)
        let id = try XCTUnwrap(model.selectedConversationID)
        model.select(model: key, for: id)
        return (model, id)
    }

    /// A reply sent on "1" and read on after the chat moved to "2" leaves
    /// its reading under "1", whether the run's report names the model by
    /// the name the list gives it, "A", or by "1": the reading is not drawn
    /// on "2", and is drawn again back on "1".
    func testAReplyReadOnAfterAMoveLeavesItsReadingUnderTheKeySent() async throws {
        for report in ["A", "1"] {
            let hub = hub(
                listing: [ModelInfo(id: "A", gglibID: 1), ModelInfo(id: "Plain", gglibID: 2)], reporting: report)
            hub.with { $0.holdAt = 2 }
            let (model, id) = try await makeModel(behind: hub, on: "1")
            let task = try XCTUnwrap(model.send("go"))
            try await Runs.until("two frames") { model.liveReply?.cursor == 2 }
            await model.scene(.background).value
            await task.value
            XCTAssertEqual(hub.with { $0.starts.last?.request.model }, "1", report)

            model.select(model: "2", for: id)
            hub.with { $0.holdAt = nil }
            await model.scene(.foreground).value
            try await Runs.until("the reply to be read on") { Runs.settled(model) }
            XCTAssertEqual(model.selectedConversation?.context?.model, "1", "reported as \(report)")
            XCTAssertNil(model.contextReading(for: try XCTUnwrap(model.selectedConversation)), report)
            model.select(model: "1", for: id)
            XCTAssertEqual(model.contextReading(for: try XCTUnwrap(model.selectedConversation))?.model, "1", report)
        }
    }

    /// A send on a profile variant, reported under its base model's name,
    /// and one on a model that shares its name with another, reported under
    /// the bare name no entry is listed as, leave the reading under the key
    /// sent, so the ring is drawn.
    func testAReportByABaseOrASharedNameKeepsTheKeySent() async throws {
        let variant = [
            ModelInfo(id: "Base", gglibID: 3), ModelInfo(id: "Base:creative", gglibID: 3, profile: "creative"),
        ]
        let shared = [ModelInfo(id: "Q@Q4_K_M", gglibID: 1), ModelInfo(id: "Q@Q8_0", gglibID: 2)]
        for (models, key, report) in [(variant, "3:creative", "Base"), (shared, "2", "Q")] {
            let hub = hub(listing: models, reporting: report)
            let (model, _) = try await makeModel(behind: hub, on: key)
            try await XCTUnwrap(model.send("go")).value
            try await Runs.until("the reply") { Runs.settled(model) }
            XCTAssertEqual(hub.with { $0.starts.last?.request.model }, key)
            let conversation = try XCTUnwrap(model.selectedConversation)
            XCTAssertEqual(model.contextReading(for: conversation)?.model, key, "reported as \(report)")
        }
    }
}
