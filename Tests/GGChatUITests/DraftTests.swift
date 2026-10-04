import GGChatCore
import XCTest

@testable import GGChatUI

/// The local composer's draft: emptied only when the model takes it, so a
/// refused draft keeps its text and its images, and the same image added
/// twice is one.
@MainActor
final class DraftTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private static func image(width: Int) throws -> DraftImage {
        try ImageDownscale().prepare(
            GeneratedImages.encode(GeneratedImages.halves(width: width, height: 32), as: .png))
    }

    /// Refused for a model that cannot see, the draft is as it was; taken
    /// once the model can, it is empty and the turn holds what it held.
    func testARefusedDraftKeepsItsTextAndImagesAndATakenOneIsEmpty() async throws {
        let (model, config) = try await Runs.makeModel(
            behind: FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning)),
            direct: true)
        let image = try Self.image(width: 64)
        var draft = Draft()
        draft.text = "what is this"
        draft.add(image)

        model.modelsByProvider[config.id] = [ModelInfo(id: "mock-27b", capabilities: nil)]
        draft.send(through: model)
        XCTAssertEqual(model.lastError, AppModel.cannotSee, "the draft was not refused")
        XCTAssertEqual(draft.text, "what is this", "a refused draft lost its text")
        XCTAssertEqual(draft.images.map(\.id), [image.id], "a refused draft lost its image")

        model.lastError = nil
        model.modelsByProvider[config.id] = [ModelInfo(id: "mock-27b", capabilities: ["vision"])]
        draft.send(through: model)
        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.images.map(\.id), [])
        XCTAssertFalse(draft.hasContent)
        let turn = try XCTUnwrap(model.selectedConversation?.messages.first)
        XCTAssertEqual(turn.content, "what is this")
        XCTAssertEqual(turn.images, [image.ref])
        try await Runs.until("the reply") { Runs.settled(model) }
    }

    /// Images are kept in the order added, the same one twice is one, and
    /// a removed one goes. A draft of spaces alone has nothing to send.
    func testTheSameImageAddedTwiceIsOne() throws {
        let (first, second) = (try Self.image(width: 64), try Self.image(width: 48))
        var draft = Draft()
        draft.text = "  \n"
        XCTAssertFalse(draft.hasContent)

        draft.add(first)
        draft.add(second)
        draft.add(first)
        XCTAssertEqual(draft.images.map(\.id), [first.id, second.id])
        XCTAssertTrue(draft.hasContent)

        draft.remove(first)
        XCTAssertEqual(draft.images.map(\.id), [second.id])
    }
}
