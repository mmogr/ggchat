import GGChatCore
import XCTest

@testable import GGChatUI

/// A message names its images, and the request is where their bytes are
/// read: once per image, from the store, for a send, Retry and a run's `PUT`
/// sent again alike. An image that cannot be read sends nothing.
final class AppModelImageRequestTests: XCTestCase {
    private typealias Runs = AppModelRunTests

    static let png = Data("PNGBYTES".utf8)
    static let image = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 64, height: 32)

    private func hub() -> FakeRunHub {
        FakeRunHub(frames: FakeRunHub.frames(ofText: Runs.text, reasoning: Runs.reasoning))
    }

    /// Counts what is read, so a test can say each image was read once.
    private final class CountingImages: ImageStore {
        var kept: [String: Data] = [:]
        var reads: [String] = []

        func save(image: ImageRef, data: Data) throws {
            kept[image.id] = data
        }

        func loadImage(id: String) throws -> Data? {
            reads.append(id)
            return kept[id]
        }

        func deleteImages(noTurnNames ids: Set<String>) throws {}
    }

    /// The open conversation, given one question that carries the image.
    @MainActor
    private func ask(_ model: AppModel) throws {
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages = [
            Message(role: .user, content: "what is this", createdAt: .distantPast, images: [Self.image])
        ]
        model.update(conversation)
    }

    /// Every image the turns name is in the request, read once however many
    /// turns name it; a request with none reads nothing and is the request
    /// it always was.
    @MainActor
    func testARequestHoldsEveryImageItsTurnsNameReadOncePerImage() throws {
        let other = Data([0xFF, 0xD8, 0xFF])
        let second = ImageRef(id: ImageRef.id(of: other), mime: ImageRef.jpeg, width: 3, height: 1)
        let store = CountingImages()
        try store.save(image: Self.image, data: Self.png)
        try store.save(image: second, data: other)
        let turns = [
            Message(role: .user, content: "one", createdAt: .distantPast, images: [Self.image]),
            Message(role: .user, content: "two", createdAt: .distantPast, images: [second, Self.image]),
        ]
        let request = try ChatRequest(model: "m", messages: turns, returnProgress: true, imagesFrom: store)
        XCTAssertEqual(request.images, [Self.image.id: Self.png, second.id: other])
        XCTAssertEqual(store.reads.sorted(), [Self.image.id, second.id].sorted())

        let plain = [Message(role: .user, content: "hi", createdAt: .distantPast)]
        let text = try ChatRequest(model: "m", messages: plain, returnProgress: false, imagesFrom: store)
        XCTAssertEqual(text, ChatRequest(model: "m", messages: plain))
        XCTAssertEqual(store.reads.count, 2, "a request with no images read one")
    }

    /// A send carries its image's bytes to the run; an image this device
    /// cannot read sends nothing and says so, and the question stays.
    @MainActor
    func testATurnsImageIsSentAndOneThatCannotBeReadSendsNothing() async throws {
        let store = RefusingStore()
        let hub = hub()
        let (model, _) = try await Runs.makeModel(behind: hub, store: store)
        try ask(model)

        XCTAssertNil(model.retry(), "a turn without its image was sent")
        XCTAssertEqual(
            model.lastError, "This device could not read an image in this conversation, so nothing was sent.")
        XCTAssertEqual(hub.with { $0.starts.count }, 0)
        XCTAssertEqual(try Runs.last(model).images, [Self.image], "the question lost its image")

        try store.save(image: Self.image, data: Self.png)
        try await XCTUnwrap(model.retry(), "the same turn with its image was not sent").value
        let sent = try XCTUnwrap(hub.with { $0.starts.first?.request })
        XCTAssertEqual(sent.images, [Self.image.id: Self.png])
        XCTAssertEqual(sent.messages.first?.images, [Self.image])
        XCTAssertEqual(try Runs.last(model).content, Runs.text)
    }

    /// A run's `PUT` whose answer was lost is sent again with the image. If
    /// the image can no longer be read by then, the reply is given up with
    /// the reason rather than sent without it.
    @MainActor
    func testARunPutAgainCarriesItsImageOrIsGivenUpWithoutIt() async throws {
        let hub = hub()
        hub.with { $0.putsLost = 1 }
        let store = RefusingStore()
        try store.save(image: Self.image, data: Self.png)
        let (model, _) = try await Runs.makeModel(behind: hub, store: store, sleeper: ReadOnSleeper(immediate: true))
        try ask(model)
        try await XCTUnwrap(model.retry()).value
        try await Runs.until("the reply to be read on") { Runs.settled(model) }
        let starts = hub.with { $0.starts.map(\.request) }
        XCTAssertEqual(starts.count, 2, "the lost PUT was not sent again")
        XCTAssertEqual(starts.last?.images, [Self.image.id: Self.png])

        let held = self.hub()
        held.with { $0.putsLost = 1 }
        let forgetting = RefusingStore()
        try forgetting.save(image: Self.image, data: Self.png)
        let (stuck, _) = try await Runs.makeModel(behind: held, store: forgetting)
        try ask(stuck)
        try await XCTUnwrap(stuck.retry()).value
        XCTAssertNotNil(try Runs.last(stuck).runID, "the lost PUT left no run to send again")
        forgetting.forgetsImages = true
        stuck.readOnDetachedRuns()
        let question = try Runs.last(stuck)
        XCTAssertNil(question.runID)
        XCTAssertEqual(question.failure, ImageUnavailable().failure)
        XCTAssertEqual(held.with { $0.starts.count }, 1, "the PUT went again without its image")
    }

    /// A direct chat to gglib is a run, so a model that cannot see takes the
    /// `PUT` and the run fails with the code. The turn says so, with the
    /// line that says what to do.
    @MainActor
    func testARunToAModelThatCannotSeeEndsWithTheCodeAndWhatToDo() async throws {
        let hub = hub()
        hub.with {
            $0.frames = []
            $0.ending = .failed
            $0.error = RunError(
                code: "model_cannot_read_images",
                message: "Model 'mock-27b' cannot read images: it has no projector linked.")
        }
        let store = RefusingStore()
        try store.save(image: Self.image, data: Self.png)
        let (model, _) = try await Runs.makeModel(behind: hub, store: store, direct: true)
        try ask(model)
        try await XCTUnwrap(model.retry()).value
        XCTAssertEqual(hub.with { $0.starts.count }, 1)
        XCTAssertEqual(hub.with { $0.chats.count }, 0, "the refusal was taken for a hub without runs")
        let failure = try XCTUnwrap(try Runs.last(model).failure)
        XCTAssertEqual(failure.code, "model_cannot_read_images")
        XCTAssertEqual(failure.hint, ProviderError.Code.modelCannotReadImages.hint)
        XCTAssertNotNil(failure.hint)
    }
}
