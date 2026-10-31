import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// A conversation kept on this phone shows its drawn picture to a model
/// gglib lists as one that reads images, and to no other: the request after
/// the draw carries the picture's bytes from this device's store, on the
/// first message after it, a kept fix replaces it, and another tool's image
/// in the same reply is passed over.
@MainActor
final class DrawnPictureShownTests: XCTestCase {
    private typealias Runs = AppModelRunTests
    private static let png = Data("A PICTURE OF A FOX".utf8)
    private static let image = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 1024, height: 1024)
    private static let fixed = Data("THE FOX, FIXED".utf8)
    private static let fix = ImageRef(id: ImageRef.id(of: fixed), mime: ImageRef.png, width: 1024, height: 1024)
    private static let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
    private static let charted = Data("A CHART OF FOXES".utf8)
    private static let chart = ImageRef(id: ImageRef.id(of: charted), mime: ImageRef.png, width: 640, height: 480)

    private struct Drawn {
        let model: AppModel
        let hub: FakeRunHub
        let store: InMemoryStore
    }

    /// A conversation here whose reply drew `image` through a run and then
    /// read `besides`, the next reply set to be words alone, and `listed` as
    /// the hub's models.
    private func drawn(listing listed: [ModelInfo], besides: [[ChatEvent]] = []) async throws -> Drawn {
        let call = ToolExchange(
            callID: "call_1", name: "builtin:generate_image", arguments: #"{"prompt":"a red fox in snow"}"#)
        let hub = FakeRunHub(
            frames: [
                [.tool("Generate Image"), .toolCalled(call)],
                [
                    .toolEnded("call_1"), .toolAnswered(callID: "call_1", text: Self.drew),
                    .images([Self.image], callID: "call_1"),
                ],
            ] + besides + [[.delta("A fox.")]])
        hub.with {
            $0.images[Self.image.id] = Self.png
            $0.images[Self.chart.id] = Self.charted
        }
        let store = InMemoryStore()
        let (model, config) = try await DrawingRunTests.makeModel(behind: hub, store: store)
        try await send(model, "a fox in snow", draws: true, until: 2)
        XCTAssertEqual(try Runs.last(model).images.first, Self.image)
        model.modelsByProvider[config.id] = listed
        hub.with { $0.frames = FakeRunHub.frames(ofText: "You are welcome.", reasoning: "") }
        return Drawn(model: model, hub: hub, store: store)
    }

    private func send(_ model: AppModel, _ text: String, draws: Bool = false, until count: Int) async throws {
        XCTAssertTrue(model.send(text, images: [], draws: draws))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == count }
    }

    private func lastSent(_ hub: FakeRunHub) throws -> ChatRequest {
        try XCTUnwrap(hub.with { $0.starts.last?.request })
    }

    /// The last message a request carries, as a server reads its content.
    private func lastContent(_ request: ChatRequest) throws -> Any? {
        let body = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        return try XCTUnwrap((body as? [String: Any])?["messages"] as? [[String: Any]]).last?["content"]
    }

    private static let sees = MockProvider.sampleModels + [ModelInfo(id: "mock-9b", capabilities: ["vision"])]

    /// A model that lists `vision` is sent the picture on the message after
    /// the draw, read from this device's store: gglib's line, the picture,
    /// then the message's words. The next request carries it on that same
    /// message, and once a fix is kept on the reply the fix is shown instead.
    func testAModelThatReadsImagesIsShownTheDrawnPicture() async throws {
        let drawn = try await drawn(listing: Self.sees)
        let (model, hub) = (drawn.model, drawn.hub)
        model.select(model: "mock-9b", for: try XCTUnwrap(model.selectedConversationID))
        try await send(model, "thanks", until: 4)
        var sent = try lastSent(hub)
        XCTAssertEqual(sent.model, "mock-9b")
        XCTAssertEqual(sent.shownPicture, ShownPicture(at: 2, image: Self.image))
        XCTAssertEqual(sent.images, [Self.image.id: Self.png])
        let parts = try XCTUnwrap(try lastContent(sent) as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["type"] as? String }, ["text", "image_url", "text"])
        XCTAssertEqual(parts.first?["text"] as? String, ShownPicture.line)
        XCTAssertEqual(
            (parts[1]["image_url"] as? [String: Any])?["url"] as? String,
            "data:image/png;base64," + Self.png.base64EncodedString())
        XCTAssertEqual(parts.last?["text"] as? String, "thanks")

        try await send(model, "what colour is it?", until: 6)
        sent = try lastSent(hub)
        XCTAssertEqual(sent.shownPicture?.at, 2, "a later request moved the picture")
        XCTAssertEqual(try lastContent(sent) as? String, "what colour is it?")

        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages[1].images.append(Self.fix)
        try drawn.store.save(image: Self.fix, data: Self.fixed)
        model.update(conversation)
        try await send(model, "and now?", until: 8)
        sent = try lastSent(hub)
        XCTAssertEqual(sent.shownPicture, ShownPicture(at: 2, image: Self.fix))
        XCTAssertEqual(sent.images, [Self.fix.id: Self.fixed], "the older picture's bytes were read")
    }

    /// A reply that drew, then searched the web and drew a chart, keeps
    /// which call made each of its images, through a save and a reading
    /// back. A model that reads images is shown the drawn picture, not the
    /// chart that came after it, and the search, which made none, hides
    /// nothing.
    func testAReplyThatDrewAndSearchedShowsItsDrawnPicture() async throws {
        let search = ToolExchange(
            callID: "call_2", name: "3:tavily_search", arguments: #"{"query":"arctic foxes"}"#,
            server: "Tavily Web Search")
        let plot = ToolExchange(callID: "call_3", name: "plot_chart", arguments: #"{"title":"foxes"}"#)
        let drawn = try await drawn(
            listing: Self.sees,
            besides: [
                [.tool("Tavily Search: arctic foxes"), .toolCalled(search)],
                [.toolEnded("call_2"), .toolAnswered(callID: "call_2", text: "They live in snow.", failed: false)],
                [.tool("Plot Chart: foxes"), .toolCalled(plot)],
                [
                    .toolEnded("call_3"), .toolAnswered(callID: "call_3", text: "[image 640x480 PNG stored]"),
                    .images([Self.chart], callID: "call_3"),
                ],
            ])
        let (model, hub) = (drawn.model, drawn.hub)
        let reply = try Runs.last(model)
        XCTAssertEqual(reply.images, [Self.image, Self.chart])
        XCTAssertEqual(reply.exchanges.map(\.images), [[Self.image.id], [], [Self.chart.id]])

        let container = SwiftDataStore.inMemoryContainer()
        try SwiftDataStore(container: container).save(conversation: try XCTUnwrap(model.selectedConversation))
        let read = try XCTUnwrap(try SwiftDataStore(container: container).loadConversations().first)
        XCTAssertEqual(read.messages.last?.exchanges, reply.exchanges, "a reopening lost which call made which")

        model.select(model: "mock-9b", for: try XCTUnwrap(model.selectedConversationID))
        try await send(model, "thanks", until: 4)
        let sent = try lastSent(hub)
        XCTAssertEqual(sent.shownPicture, ShownPicture(at: 2, image: Self.image))
        XCTAssertEqual(sent.images, [Self.image.id: Self.png], "the chart's bytes were read for the model")
        let parts = try XCTUnwrap(try lastContent(sent) as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, ShownPicture.line)
        XCTAssertEqual(
            (parts[1]["image_url"] as? [String: Any])?["url"] as? String,
            "data:image/png;base64," + Self.png.base64EncodedString())
    }

    /// A model gglib lists without `vision`, and one its list does not
    /// name, are sent the chat as before: no picture and no bytes read.
    func testAModelThatDoesNotListVisionIsNotShownIt() async throws {
        let drawn = try await drawn(listing: Self.sees)
        let (model, hub) = (drawn.model, drawn.hub)
        try await send(model, "thanks", until: 4)
        var sent = try lastSent(hub)
        XCTAssertEqual(sent.model, "mock-27b")
        XCTAssertTrue(sent.replaysToolCalls)
        XCTAssertNil(sent.shownPicture, "a model that cannot read images was shown the picture")
        XCTAssertEqual(sent.images, [:], "the picture's bytes were read for the model")
        XCTAssertEqual(try lastContent(sent) as? String, "thanks")

        model.select(model: "not-listed", for: try XCTUnwrap(model.selectedConversationID))
        try await send(model, "and again", until: 6)
        sent = try lastSent(hub)
        XCTAssertEqual(sent.model, "not-listed")
        XCTAssertNil(sent.shownPicture, "a model gglib does not list was shown the picture")
        XCTAssertEqual(sent.images, [:])
    }

    /// A server not known to be gglib is not sent the picture, even for a
    /// model its list says reads images: it is not sent how the picture
    /// was made either, so no bytes are read and the message is its words.
    func testAServerThatIsNotGglibIsNotShownIt() async throws {
        let recorder = RecordingProvider(
            wrapping: MockProvider(models: Self.sees, scripts: [.init(text: "You are welcome.")]))
        let store = InMemoryStore()
        let (model, config) = try await Runs.makeModel(behind: recorder, store: store, direct: true)
        model.proxyStatusAvailability[config.id] = false
        XCTAssertFalse(model.speaksGGLib(config))
        model.modelsByProvider[config.id] = Self.sees
        let id = try XCTUnwrap(model.selectedConversationID)
        model.select(model: "mock-9b", for: id)
        var question = Message(role: .user, content: "a fox in snow", createdAt: .distantPast)
        question.draws = true
        var reply = Message(role: .assistant, content: "A fox.", createdAt: .distantPast, images: [Self.image])
        reply.exchanges = [
            ToolExchange(callID: "call_1", name: HubToolCall.drawingTool, arguments: "{}", result: Self.drew)
        ]
        try store.save(image: Self.image, data: Self.png)
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages = [question, reply]
        model.update(conversation)

        try await XCTUnwrap(model.send("thanks")).value
        let sent = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(sent.model, "mock-9b")
        XCTAssertFalse(sent.replaysToolCalls)
        XCTAssertNotNil(sent.messages.shownPicture, "the chat sent holds no drawn picture to leave out")
        XCTAssertNil(sent.shownPicture, "a server not known to be gglib was shown the picture")
        XCTAssertEqual(sent.images, [:], "the picture's bytes were read for a server not known to be gglib")
        XCTAssertEqual(try lastContent(sent) as? String, "thanks")
    }

    /// A picture whose bytes this device no longer has is left out, and the
    /// message is still sent, as it would be to a model that cannot see.
    func testAPictureWhoseBytesAreGoneIsLeftOut() async throws {
        let drawn = try await drawn(listing: Self.sees)
        let (model, hub) = (drawn.model, drawn.hub)
        model.select(model: "mock-9b", for: try XCTUnwrap(model.selectedConversationID))
        var conversation = try XCTUnwrap(model.selectedConversation)
        conversation.messages[1].images = [ImageRef(id: "gone", mime: ImageRef.png, width: 1, height: 1)]
        model.update(conversation)
        try await send(model, "thanks", until: 4)
        let sent = try lastSent(hub)
        XCTAssertNil(sent.shownPicture)
        XCTAssertEqual(sent.images, [:])
        XCTAssertEqual(try lastContent(sent) as? String, "thanks")
    }
}
