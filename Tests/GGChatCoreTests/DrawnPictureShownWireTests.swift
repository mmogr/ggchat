import XCTest

@testable import GGChatCore

/// The drawn picture shown to a model that reads images, by gglib's rule for
/// a client that keeps its own chats (gglib's `docs/clients.md`, Images): on
/// the first `user` message after the draw, gglib's line, the picture, then
/// the message's own parts; the newest picture only; the same message on
/// every later request, until a newer picture moves it.
final class DrawnPictureShownWireTests: XCTestCase {
    private static let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
    private static let fox = Data("A PICTURE OF A FOX".utf8)
    private static let fixed = Data("THE FOX, FIXED".utf8)
    private static let bluer = Data("A BLUER FOX".utf8)
    private static let attached = Data("THE PERSON'S OWN PHOTO".utf8)
    private static let photo = Data("A PHOTO ANOTHER TOOL TOOK".utf8)

    private static func ref(_ data: Data) -> ImageRef {
        ImageRef(id: ImageRef.id(of: data), mime: ImageRef.png, width: 1024, height: 1024)
    }

    private static let bytes = [fox, fixed, bluer, attached, photo].reduce(into: [String: Data]()) {
        $0[ref($1).id] = $1
    }

    private func said(_ role: Role, _ text: String, images: [Data] = []) -> Message {
        Message(role: role, content: text, createdAt: .distantPast, images: images.map(Self.ref))
    }

    /// A turn that drew: the question sent with Draw, and the reply holding
    /// `pictures` and the drawing tool's call under `id`, answered unless
    /// `answer` is nil.
    private func drawn(
        _ pictures: [Data], id: String = "call_1", tool: String = HubToolCall.drawingTool, answer: String? = drew
    ) -> [Message] {
        var question = said(.user, "a fox in snow")
        question.draws = true
        var reply = said(.assistant, "A fox.", images: pictures)
        reply.exchanges = [ToolExchange(callID: id, name: tool, arguments: #"{"prompt":"a fox"}"#, result: answer)]
        return [question, reply]
    }

    /// The request gglib is sent for a model that reads images: the calls
    /// replayed and the picture the messages show, with every image's bytes.
    private func request(_ messages: [Message]) -> ChatRequest {
        ChatRequest(
            model: "m", messages: messages, images: Self.bytes, replaysToolCalls: true,
            shownPicture: messages.shownPicture)
    }

    /// Each sent message's content as a server reads it: a bare string as
    /// itself, and a list of parts as `text:` or `image:` and its value.
    private func contents(_ request: ChatRequest) throws -> [[String]] {
        let body = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        let messages = try XCTUnwrap((body as? [String: Any])?["messages"] as? [[String: Any]])
        return messages.map { message in
            if let text = message["content"] as? String { return [text] }
            return (message["content"] as? [[String: Any]] ?? []).map { part in
                if let text = part["text"] as? String { return "text:" + text }
                return "image:" + ((part["image_url"] as? [String: Any])?["url"] as? String ?? "")
            }
        }
    }

    private static func url(_ data: Data) -> String {
        "image:data:image/png;base64," + data.base64EncodedString()
    }

    /// The first message after the draw is sent as gglib's line, word for
    /// word, then the picture as a data URL, then its own text and its own
    /// image, in that order; the history ahead of it is what it was.
    func testTheMessageAfterADrawCarriesTheLineThePictureThenItsOwnParts() throws {
        XCTAssertEqual(
            ShownPicture.line,
            "(Added automatically, not written by the person: the image below is the most recent picture the drawing"
                + " tool made in this conversation, the same one the person sees. You can see it now, although the"
                + " tool's answer said you could not. The person's own message follows.)")
        let messages = drawn([Self.fox]) + [said(.user, "what colour is it?", images: [Self.attached])]
        XCTAssertEqual(messages.shownPicture, ShownPicture(at: 2, image: Self.ref(Self.fox)))
        let sent = try contents(request(messages))
        XCTAssertEqual(sent.count, 5, "the call and its answer were not sent ahead of the reply")
        XCTAssertEqual(sent[0], ["a fox in snow"])
        XCTAssertEqual(sent[3], ["A fox."], "the reply was sent its picture")
        XCTAssertEqual(
            sent[4],
            ["text:" + ShownPicture.line, Self.url(Self.fox), "text:what colour is it?", Self.url(Self.attached)])

        let bare = try contents(request(drawn([Self.fox]) + [said(.user, "")]))
        XCTAssertEqual(bare.last, ["text:" + ShownPicture.line, Self.url(Self.fox)])
    }

    /// Only the newest picture is shown: a kept fix appended to the reply
    /// rather than the picture it came from, and the later of two drawn
    /// replies rather than the earlier.
    func testOnlyTheNewestPictureIsShown() throws {
        let kept = drawn([Self.fox, Self.fixed]) + [said(.user, "thanks")]
        XCTAssertEqual(kept.shownPicture?.image, Self.ref(Self.fixed))
        XCTAssertEqual(
            try contents(request(kept)).last, ["text:" + ShownPicture.line, Self.url(Self.fixed), "text:thanks"])

        let two = drawn([Self.fox]) + drawn([Self.bluer], id: "call_2") + [said(.user, "thanks")]
        XCTAssertEqual(two.shownPicture, ShownPicture(at: 4, image: Self.ref(Self.bluer)))
        let sent = try contents(request(two))
        XCTAssertEqual(sent.filter { $0.contains(Self.url(Self.fox)) }, [], "an older picture was sent")
        XCTAssertEqual(sent.last, ["text:" + ShownPicture.line, Self.url(Self.bluer), "text:thanks"])
    }

    /// Every later request carries it on the same message, the first after
    /// the draw, and the messages after that are sent as they were written.
    func testTheSameMessageCarriesItOnEveryLaterRequest() throws {
        var messages = drawn([Self.fox]) + [said(.user, "thanks")]
        XCTAssertEqual(messages.shownPicture?.at, 2)
        messages += [said(.assistant, "You are welcome."), said(.user, "what colour is it?")]
        XCTAssertEqual(messages.shownPicture?.at, 2)
        messages += [said(.assistant, "Red."), said(.user, "and the snow?")]
        XCTAssertEqual(messages.shownPicture, ShownPicture(at: 2, image: Self.ref(Self.fox)))
        let sent = try contents(request(messages))
        XCTAssertEqual(sent[4], ["text:" + ShownPicture.line, Self.url(Self.fox), "text:thanks"])
        XCTAssertEqual(Array(sent[5...]), [["You are welcome."], ["what colour is it?"], ["Red."], ["and the snow?"]])
    }

    /// A newer picture goes on the message after it, and the message that
    /// carried the older one is sent as text again. A question sent with
    /// Draw is a person's message too, and carries the picture before it.
    func testANewerPictureMovesToTheMessageAfterIt() throws {
        var question = said(.user, "a bluer one")
        question.draws = true
        let before = drawn([Self.fox]) + [said(.user, "thanks"), said(.assistant, "Welcome."), question]
        XCTAssertEqual(before.shownPicture?.at, 2)
        var reply = said(.assistant, "Bluer.", images: [Self.bluer])
        reply.exchanges = [
            ToolExchange(callID: "call_2", name: HubToolCall.drawingTool, arguments: "{}", result: Self.drew)
        ]
        let after = before + [reply, said(.user, "better")]
        XCTAssertEqual(after.shownPicture, ShownPicture(at: 6, image: Self.ref(Self.bluer)))
        let sent = try contents(request(after))
        XCTAssertEqual(sent[4], ["thanks"], "the older message kept its picture")
        XCTAssertEqual(sent[6], ["a bluer one"])
        XCTAssertEqual(sent.last, ["text:" + ShownPicture.line, Self.url(Self.bluer), "text:better"])
    }

    /// No picture is shown where none was drawn: a reply that holds no
    /// call, a call nothing answered, another tool's picture, or a draw
    /// that failed and so made none, which leaves the picture before it
    /// shown. Nor before a message follows it. A request that shows none
    /// is the one it always was, and one whose bytes are missing is not
    /// sent without them.
    func testNoDrawnPictureNoPicture() throws {
        var before = said(.assistant, "A fox.", images: [Self.fox])
        XCTAssertNil(([said(.user, "a fox")] + [before, said(.user, "thanks")]).shownPicture)
        before.exchanges = [ToolExchange(callID: "c", name: "mcp:camera", arguments: "{}", result: "took one")]
        XCTAssertNil(([said(.user, "a fox")] + [before, said(.user, "thanks")]).shownPicture)
        XCTAssertNil((drawn([Self.fox], answer: nil) + [said(.user, "thanks")]).shownPicture)
        XCTAssertNil((drawn([Self.fox], tool: "builtin:generate_imagery") + [said(.user, "thanks")]).shownPicture)
        XCTAssertNil(drawn([Self.fox]).shownPicture, "a picture was put on no message")

        let failed = drawn([Self.fox]) + drawn([], id: "call_2", answer: "image_generation_failed: lost")
        XCTAssertEqual((failed + [said(.user, "again?")]).shownPicture, ShownPicture(at: 2, image: Self.ref(Self.fox)))

        let plain = ChatRequest(
            model: "m", messages: drawn([Self.fox]) + [said(.user, "thanks")], replaysToolCalls: true)
        XCTAssertEqual(try contents(plain).last, ["thanks"])
        var missing = request(drawn([Self.fox]) + [said(.user, "thanks")])
        missing.images = [:]
        XCTAssertThrowsError(try ChatCompletionRequest(missing))
    }

    /// A reply that drew and then had another tool answer with an image
    /// holds both tools' images, and the other tool's is passed over though
    /// it came last: the drawn picture is shown, and neither the other's
    /// nor an older drawn one is sent. A call the other tool never answered
    /// made none, so the reply's last image is no call's, as a kept fix is,
    /// and it is the one shown.
    func testAReplyThatDrewAndCalledAnotherToolShowsTheDrawnPicture() throws {
        var reply = said(.assistant, "A fox, and a photo.", images: [Self.fox, Self.photo])
        reply.exchanges = [
            ToolExchange(callID: "call_2", name: HubToolCall.drawingTool, arguments: "{}", result: Self.drew),
            ToolExchange(
                callID: "call_3", name: "mcp:camera", arguments: "{}", result: "took one",
                images: [Self.ref(Self.photo).id]),
        ]
        let messages = drawn([Self.bluer]) + [said(.user, "a fox"), reply, said(.user, "thanks")]
        XCTAssertEqual(
            messages.shownPicture, ShownPicture(at: 4, image: Self.ref(Self.fox)),
            "another tool's image was shown as the drawn picture")
        let sent = try contents(request(messages))
        XCTAssertEqual(sent.last, ["text:" + ShownPicture.line, Self.url(Self.fox), "text:thanks"])
        XCTAssertEqual(sent.filter { $0.contains(Self.url(Self.photo)) || $0.contains(Self.url(Self.bluer)) }, [])

        var pending = reply
        pending.exchanges[1] = ToolExchange(callID: "call_3", name: "mcp:camera", arguments: "{}", result: nil)
        let unanswered = drawn([Self.bluer]) + [said(.user, "a fox"), pending, said(.user, "thanks")]
        XCTAssertEqual(
            unanswered.shownPicture, ShownPicture(at: 4, image: Self.ref(Self.photo)), "an unanswered call hid it")
    }

    /// A draw that failed beside another tool that answered with an image
    /// leaves that image the reply's only one, and it is not shown.
    func testAFailedDrawBesideAnotherToolsImageShowsNoPicture() throws {
        var reply = said(.assistant, "No fox, but a photo.", images: [Self.photo])
        reply.exchanges = [
            ToolExchange(
                callID: "call_1", name: HubToolCall.drawingTool, arguments: "{}",
                result: "image_generation_failed: lost"),
            ToolExchange(
                callID: "call_2", name: "mcp:camera", arguments: "{}", result: "took one",
                images: [Self.ref(Self.photo).id]),
        ]
        let messages = [said(.user, "a fox"), reply, said(.user, "thanks")]
        XCTAssertNil(messages.shownPicture, "another tool's image was shown beside a failed draw")
        XCTAssertEqual(try contents(request(messages)).last, ["thanks"])
    }
}
