import GGChatCore
import XCTest

@testable import GGChatUI

/// A draft is text, images, or both. gglib says which of its models can
/// see, and a draft with images to one that cannot is refused here with
/// gglib's own sentence and left as it was. A draft taken is a turn that
/// names its images, their bytes kept on this device, and a turn the server
/// refuses keeps them for Retry.
final class AppModelImageSendTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    /// An image as the composer holds one, made by the one downscale.
    private static func draftImage() throws -> DraftImage {
        try ImageDownscale().prepare(
            GeneratedImages.encode(GeneratedImages.halves(width: 64, height: 32), as: .png))
    }

    /// The model the conversation talks to, as the list says it is.
    @MainActor
    private func list(_ model: AppModel, _ config: ProviderConfig, capabilities: [String]?) {
        model.modelsByProvider[config.id] = [ModelInfo(id: "mock-27b", capabilities: capabilities)]
    }

    /// Only a gglib server says a model cannot see, and only of a model its
    /// list names without `vision`. Any other server, and a model the list
    /// does not name, is sent images.
    @MainActor
    func testOnlyAModelGGLibListsWithoutVisionCannotSee() async throws {
        let (model, config) = try await Runs.makeModel(behind: hub(), direct: true)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(model.asksForProgress(config))

        list(model, config, capabilities: nil)
        XCTAssertFalse(model.canSee(conversation), "gglib's model without vision was sent images")
        list(model, config, capabilities: ["tools"])
        XCTAssertFalse(model.canSee(conversation))
        list(model, config, capabilities: ["vision"])
        XCTAssertTrue(model.canSee(conversation), "gglib's model with vision was refused images")
        model.modelsByProvider[config.id] = [ModelInfo(id: "another-model")]
        XCTAssertTrue(model.canSee(conversation), "a model the list does not name was taken to be blind")

        list(model, config, capabilities: nil)
        model.proxyStatusAvailability[config.id] = false
        XCTAssertFalse(model.asksForProgress(config))
        XCTAssertTrue(model.canSee(conversation), "a server not known to be gglib was taken to be blind")
    }

    /// A draft with an image to a model that cannot see is refused here with
    /// gglib's sentence: no turn, no bytes kept, nothing sent. A draft of
    /// text alone still goes to it, and the draft with the image goes once
    /// the model can see.
    @MainActor
    func testADraftWithAnImageToAModelThatCannotSeeIsRefusedHere() async throws {
        let hub = hub()
        let store = InMemoryStore()
        let (model, config) = try await Runs.makeModel(behind: hub, store: store, direct: true)
        let image = try Self.draftImage()
        list(model, config, capabilities: nil)

        XCTAssertFalse(model.send("what is this", images: [image]))
        XCTAssertEqual(model.lastError, ProviderError.Code.modelCannotReadImages.hint)
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(AppModel.cannotSee, ProviderError.Code.modelCannotReadImages.hint)
        XCTAssertEqual(model.selectedConversation?.messages, [], "a refused draft became a turn")
        XCTAssertNil(try store.loadImage(id: image.id), "a refused draft's image was kept")
        XCTAssertEqual(hub.with { $0.starts.count }, 0)

        model.lastError = nil
        XCTAssertTrue(model.send("hi", images: []), "a draft of text alone was refused a model that cannot see")
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.selectedConversation?.messages.first?.content, "hi")
        XCTAssertEqual(hub.with { $0.starts.count }, 1)

        list(model, config, capabilities: ["vision"])
        XCTAssertTrue(model.send("what is this", images: [image]))
        try await Runs.until("the reply") { Runs.settled(model) }
        XCTAssertNil(model.lastError)
        XCTAssertEqual(hub.with { $0.starts.count }, 2)
        XCTAssertEqual(hub.with { $0.starts.last?.request.images }, [image.id: image.data])
    }

    /// An image added for a model that cannot see is refused as it is
    /// added, with gglib's sentence; one for a model that can is let in.
    @MainActor
    func testAnImageAddedForAModelThatCannotSeeIsRefusedAtOnce() async throws {
        let (model, config) = try await Runs.makeModel(behind: hub(), direct: true)
        let conversation = try XCTUnwrap(model.selectedConversation)

        list(model, config, capabilities: ["vision"])
        XCTAssertTrue(model.admitsImages(to: conversation))
        XCTAssertNil(model.lastError)

        list(model, config, capabilities: nil)
        XCTAssertFalse(model.admitsImages(to: conversation))
        XCTAssertEqual(model.lastError, AppModel.cannotSee)
    }

    /// A draft refused partway through keeping its images takes back the
    /// ones it kept, so no image is left that no turn names. An image an
    /// earlier turn sent stays.
    @MainActor
    func testARefusedDraftLeavesNoImageBehindThatNoTurnNames() async throws {
        let store = RefusingStore()
        let (model, config) = try await Runs.makeModel(behind: hub(), store: store, direct: true)
        list(model, config, capabilities: ["vision"])
        let images = try [64, 48, 40].map { width in
            try ImageDownscale().prepare(
                GeneratedImages.encode(GeneratedImages.halves(width: width, height: 32), as: .png))
        }
        XCTAssertEqual(Set(images.map(\.id)).count, 3)
        let (sent, kept, refused) = (images[0], images[1], images[2])
        XCTAssertTrue(model.send("first", images: [sent]))
        try await Runs.until("the reply") { Runs.settled(model) }

        store.imagesBeforeRefusing = 1
        XCTAssertFalse(model.send("next", images: [kept, refused]))
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(store.imagesBeforeRefusing, 0, "the first image was never kept")
        XCTAssertNil(try store.loadImage(id: kept.id), "a refused draft's image was left in the store")

        store.imagesBeforeRefusing = 1
        XCTAssertFalse(model.send("again", images: [sent, refused]))
        XCTAssertEqual(try store.loadImage(id: sent.id), sent.data, "an earlier turn's image was taken back")
        XCTAssertEqual(model.selectedConversation?.messages.count, 2)
    }

    /// A turn of images alone is sent: the turn names them with no text,
    /// their bytes are kept under their ids, the request carries them, and
    /// the conversation is called what its first turn holds. A draft with
    /// neither is not a turn.
    @MainActor
    func testATurnOfImagesAloneIsSentAndItsBytesAreKept() async throws {
        let hub = hub()
        let store = InMemoryStore()
        let (model, config) = try await Runs.makeModel(behind: hub, store: store, direct: true)
        list(model, config, capabilities: ["vision"])
        let image = try Self.draftImage()

        XCTAssertFalse(model.send("  ", images: []), "a draft with neither text nor image was taken")
        XCTAssertTrue(model.send("  ", images: [image]))
        try await Runs.until("the reply") { Runs.settled(model) }

        let question = try XCTUnwrap(model.selectedConversation?.messages.first)
        XCTAssertEqual(question.content, "")
        XCTAssertEqual(question.images, [image.ref])
        XCTAssertEqual(try store.loadImage(id: image.id), image.data)
        let sent = try XCTUnwrap(hub.with { $0.starts.first?.request })
        XCTAssertEqual(sent.images, [image.id: image.data])
        XCTAssertEqual(sent.messages.last?.images, [image.ref])
        XCTAssertEqual(model.selectedConversation?.derivedTitle, "An image")
        XCTAssertEqual(try Runs.last(model).content, Runs.text)

        let picture = try XCTUnwrap(model.thumbnail(of: image.ref), "the row has no picture of the kept image")
        XCTAssertEqual([picture.width, picture.height], [64, 32])
        XCTAssertNotNil(model.picture(of: image.ref))
        XCTAssertNil(model.thumbnail(of: ImageRef(id: "absent", mime: ImageRef.png, width: 1, height: 1)))
    }

    /// A draft whose image this device could not keep is refused, so the
    /// composer keeps it; nothing is sent without it.
    @MainActor
    func testADraftWhoseImageCannotBeKeptIsRefused() async throws {
        let hub = hub()
        let store = RefusingStore()
        let (model, config) = try await Runs.makeModel(behind: hub, store: store, direct: true)
        list(model, config, capabilities: ["vision"])
        store.refusesSaves = true

        XCTAssertFalse(model.send("look", images: [try Self.draftImage()]))
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.selectedConversation?.messages, [])
        XCTAssertEqual(hub.with { $0.starts.count }, 0)
    }

    /// A turn the server refuses keeps its images with it, so Retry sends
    /// the same images again.
    @MainActor
    func testATurnTheServerRefusesKeepsItsImagesForRetry() async throws {
        let hub = hub()
        hub.with {
            $0.frames = []
            $0.ending = .failed
            $0.error = RunError(code: "model_cannot_read_images", message: "Model 'mock-27b' cannot read images.")
        }
        let (model, config) = try await Runs.makeModel(behind: hub, direct: true)
        list(model, config, capabilities: ["vision"])
        let image = try Self.draftImage()

        XCTAssertTrue(model.send("what is this", images: [image]))
        try await Runs.until("the refusal") { Runs.settled(model) }
        let refused = try Runs.last(model)
        XCTAssertEqual(refused.failure?.code, "model_cannot_read_images")
        XCTAssertEqual(refused.images, [image.ref], "the refused turn lost its image")

        hub.with {
            $0.frames = FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning)
            $0.ending = .completed
            $0.error = nil
        }
        try await XCTUnwrap(model.retry()).value
        try await Runs.until("the reply") { Runs.settled(model) }
        let starts = hub.with { $0.starts.map(\.request) }
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts.last?.images, [image.id: image.data])
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
    }

    /// Each image in the strip says what gglib estimates it costs.
    @MainActor
    func testEachImageInTheStripSaysWhatGGLibEstimatesItCosts() {
        XCTAssertEqual(
            AttachmentStrip.cost(of: ImageRef(id: "a", mime: ImageRef.png, width: 2560, height: 1440)), "~3600 tokens")
        XCTAssertEqual(
            AttachmentStrip.cost(of: ImageRef(id: "b", mime: ImageRef.png, width: 33, height: 1)), "~2 tokens")
    }
}
