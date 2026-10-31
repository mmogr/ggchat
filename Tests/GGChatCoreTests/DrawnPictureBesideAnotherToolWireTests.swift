import XCTest

@testable import GGChatCore

/// A reply that drew and called another tool too, a web search or a chart,
/// shows a model that reads images its drawn picture: each answered call
/// keeps the ids of the images it made (``ToolExchange/images``), so the
/// other tool's are passed over. Only a reply kept before calls kept their
/// images, where which call made which is not known, still shows none.
final class DrawnPictureBesideAnotherToolWireTests: XCTestCase {
    private static let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
    private static let fox = Data("A PICTURE OF A FOX".utf8)
    private static let chart = Data("A CHART OF FOXES".utf8)
    private static let fixed = Data("THE FOX, FIXED".utf8)
    private static let older = Data("AN OLDER FOX".utf8)

    private static func ref(_ data: Data) -> ImageRef {
        ImageRef(id: ImageRef.id(of: data), mime: ImageRef.png, width: 1024, height: 1024)
    }

    private func said(_ role: Role, _ text: String, images: [Data] = []) -> Message {
        Message(role: role, content: text, createdAt: .distantPast, images: images.map(Self.ref))
    }

    /// An answered call of the drawing tool under `id` that made `made`.
    private static func draw(_ id: String = "call_1", made: [Data]? = [fox]) -> ToolExchange {
        ToolExchange(
            callID: id, name: HubToolCall.drawingTool, arguments: #"{"prompt":"a fox"}"#, result: drew,
            images: made.map { $0.map { ref($0).id } })
    }

    /// An answered call of an MCP server's tool that made `made`: none for
    /// a search, and nil for one kept before calls kept their images.
    private static func other(_ name: String = "3:tavily_search", made: [Data]?) -> ToolExchange {
        ToolExchange(
            callID: "call_" + name, name: name, arguments: "{}", result: "found some", server: "Tavily Web Search",
            images: made.map { $0.map { ref($0).id } })
    }

    /// A question sent with Draw, then the reply holding `pictures` and
    /// `exchanges`.
    private func turn(_ pictures: [Data], _ exchanges: [ToolExchange]) -> [Message] {
        var question = said(.user, "a fox in snow, and what lives there")
        question.draws = true
        var reply = said(.assistant, "A fox, and what I found.", images: pictures)
        reply.exchanges = exchanges
        return [question, reply]
    }

    /// A reply read from gglib's frames, as a run being read gathers it: a
    /// draw that made the fox, then a web search that made nothing. The
    /// next request to a model that reads images carries the fox on the
    /// person's next message, after gglib's line.
    func testADrawBesideASearchThatMadeNoImageIsShown() throws {
        let frames = [
            #"{"type":"tool_call_start","tool_call":{"id":"call_1","name":"builtin:generate_image","#
                + #""arguments":{"prompt":"a fox"}}}"#,
            #"{"type":"tool_call_complete","result":{"tool_call_id":"call_1","content":"\#(Self.drew)","#
                + #""success":true,"images":[{"id":"\#(Self.ref(Self.fox).id)","mime":"image/png","width":1024,"#
                + #""height":1024}]}}"#,
            #"{"type":"tool_call_start","server":"Tavily Web Search","tool_call":{"id":"call_2","#
                + #""name":"3:tavily_search","arguments":{"query":"arctic foxes"}}}"#,
            #"{"type":"tool_call_complete","result":{"tool_call_id":"call_2","content":"They live in snow.","#
                + #""success":true}}"#,
        ]
        var reply = said(.assistant, "A fox, and where they live.")
        for frame in frames {
            for event in OpenAICompatibleProvider.agentEvents(SSEEvent(data: frame)) {
                reply.exchanges.take(event)
                if case .images(let images, _) = event { reply.images += images }
            }
        }
        XCTAssertEqual(reply.exchanges.map(\.images), [[Self.ref(Self.fox).id], []])
        let messages = [said(.user, "a fox in snow"), reply, said(.user, "what colour is it?")]
        XCTAssertEqual(messages.shownPicture, ShownPicture(at: 2, image: Self.ref(Self.fox)))

        let request = ChatRequest(
            model: "m", messages: messages, images: [Self.ref(Self.fox).id: Self.fox], replaysToolCalls: true,
            shownPicture: messages.shownPicture)
        let body = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        let sent = try XCTUnwrap((body as? [String: Any])?["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(sent.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, ShownPicture.line)
        XCTAssertEqual(
            (parts[1]["image_url"] as? [String: Any])?["url"] as? String,
            "data:image/png;base64," + Self.fox.base64EncodedString())
        XCTAssertEqual(parts.last?["text"] as? String, "what colour is it?")
    }

    /// Another tool's image is passed over though it is the reply's last:
    /// the drawn picture is shown, and a fix or a redo kept on the reply,
    /// which is no call's, is shown after it.
    func testAnotherToolsImageIsPassedOverAndAKeptFixIsStillShown() {
        let charted = turn([Self.fox, Self.chart], [Self.draw(), Self.other("plot_chart", made: [Self.chart])])
        XCTAssertEqual(
            (charted + [said(.user, "thanks")]).shownPicture, ShownPicture(at: 2, image: Self.ref(Self.fox)),
            "another tool's image was shown as the drawn picture")

        let kept = turn(
            [Self.fox, Self.chart, Self.fixed], [Self.draw(), Self.other("plot_chart", made: [Self.chart])])
        XCTAssertEqual((kept + [said(.user, "thanks")]).shownPicture?.image, Self.ref(Self.fixed))
    }

    /// A reply whose draw failed beside a tool that made an image drew
    /// nothing, so the picture drawn before it is the most recent and is
    /// shown, on the message after its own reply.
    func testAReplyWhoseEveryImageAnotherToolMadeShowsThePictureBefore() {
        let failed = ToolExchange(
            callID: "call_2", name: HubToolCall.drawingTool, arguments: "{}", result: "image_generation_failed: lost",
            images: [])
        let messages =
            turn([Self.older], [Self.draw(made: [Self.older])]) + [said(.user, "and a chart?")]
            + turn([Self.chart], [failed, Self.other("plot_chart", made: [Self.chart])]) + [said(.user, "thanks")]
        XCTAssertEqual(messages.shownPicture, ShownPicture(at: 2, image: Self.ref(Self.older)))
    }

    /// A reply kept before calls kept their images, whose other tool
    /// answered, still shows none, not even an older picture: its last
    /// image may be that tool's, and one in it may be newer. A draw kept
    /// then beside no other tool is shown as it always was.
    func testAReplyKeptBeforeCallsKeptTheirImagesStillShowsNone() {
        let unknown = turn([Self.fox], [Self.draw(made: nil), Self.other(made: nil)])
        XCTAssertNil((unknown + [said(.user, "thanks")]).shownPicture)
        let before = turn([Self.older], [Self.draw(made: [Self.older])]) + [said(.user, "another")]
        XCTAssertNil((before + unknown + [said(.user, "thanks")]).shownPicture, "an older picture was shown")

        let alone = turn([Self.fox], [Self.draw(made: nil)])
        XCTAssertEqual((alone + [said(.user, "thanks")]).shownPicture, ShownPicture(at: 2, image: Self.ref(Self.fox)))
    }
}
