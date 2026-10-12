import Foundation
import XCTest

@testable import GGChatCore

/// A picture drawn again, on the wire: what a brush stroke is placed by,
/// the body `images/generations` is sent, the stream it answers read to the
/// picture or to why there is none, and the picture kept in a hub's chat.
final class PictureRedrawWireTests: XCTestCase {
    private let picture = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    private let mask = Data([0x89, 0x50, 0x4E, 0x47, 9, 9])

    private func body(_ redraw: PictureRedraw) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(redraw))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func frame(_ event: String, _ data: String) -> String {
        "event: \(event)\ndata: \(data)\n\n"
    }

    /// Reads a whole redraw from `host`, which answers `images/generations`
    /// with `answer`.
    private func events(_ answer: ChatsHub.Answer, at host: String) async -> [RedrawEvent] {
        ChatsHub.serve(answer, at: "/v1/images/generations", on: host)
        var events: [RedrawEvent] = []
        let redraw = PictureRedraw(prompt: "a fox", image: picture, strength: 0.4)
        for await event in ChatsHub.provider(at: host).redraw(redraw) { events.append(event) }
        return events
    }

    /// A pointer over the picture on screen is a point in the picture's own
    /// pixels, whatever size it is shown at; one outside is held to the
    /// nearest edge, and a box with no size is the top left.
    func testAPointerIsPlacedInThePicturesPixelsAndHeldInside() {
        let box = CGRect(x: 20, y: 100, width: 200, height: 100)
        let natural = CGSize(width: 1024, height: 512)
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: 120, y: 150), in: box, of: natural), CGPoint(x: 512, y: 256))
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: 20, y: 100), in: box, of: natural), .zero)
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: 70, y: 125), in: box, of: natural), CGPoint(x: 256, y: 128))
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: -5, y: 90), in: box, of: natural), .zero)
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: 900, y: 900), in: box, of: natural), CGPoint(x: 1024, y: 512))
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: 120, y: 900), in: box, of: natural), CGPoint(x: 512, y: 512))
        XCTAssertEqual(MaskStroke.point(at: CGPoint(x: 50, y: 50), in: .zero, of: natural), .zero)
    }

    /// Strokes mark something once one of them paints: none, rubbing out
    /// alone, and a stroke with no points mark nothing.
    func testOnlyAStrokeThatPaintsMarksSomething() {
        let dot = [CGPoint(x: 4, y: 4)]
        XCTAssertFalse([MaskStroke]().marksSomething)
        XCTAssertFalse([MaskStroke(points: dot, width: 8, erases: true)].marksSomething)
        XCTAssertFalse([MaskStroke(points: [], width: 8)].marksSomething)
        XCTAssertTrue(
            [MaskStroke(points: dot, width: 8, erases: true), MaskStroke(points: dot, width: 8)].marksSomething)
    }

    /// A fix is the picture and its mask as base64, the prompt without the
    /// space around it, the strength, the chosen model's id as text, and
    /// `stream`.
    func testAFixSendsThePictureItsMaskItsStrengthAndItsModelAsText() throws {
        let sent = try body(
            PictureRedraw(prompt: "  a fox's paw\n", image: picture, mask: mask, strength: 0.75, model: 7))
        XCTAssertEqual(Set(sent.keys), ["prompt", "image", "mask", "strength", "model", "stream"])
        XCTAssertEqual(sent["prompt"] as? String, "a fox's paw")
        XCTAssertEqual(sent["image"] as? String, picture.base64EncodedString())
        XCTAssertEqual(sent["mask"] as? String, mask.base64EncodedString())
        XCTAssertEqual(sent["strength"] as? Double, 0.75)
        XCTAssertEqual(sent["model"] as? String, "7")
        XCTAssertEqual(sent["stream"] as? Bool, true)
    }

    /// A redo has no `mask` key, and the Mac's own choice of model no
    /// `model` key; a strength the slider left a hair off its step is sent
    /// to two places.
    func testARedoSendsNoMaskAndTheMacsOwnChoiceNoModel() throws {
        let sent = try body(PictureRedraw(prompt: "a fox", image: picture, strength: 0.1 + 0.05 * 6))
        XCTAssertEqual(Set(sent.keys), ["prompt", "image", "strength", "stream"])
        XCTAssertEqual(sent["strength"] as? Double, 0.4)
        XCTAssertEqual(sent["stream"] as? Bool, true)
    }

    /// The stream is read as its progress, each with its numbers and its
    /// frame, then the first picture, where the reading stops: a partial
    /// image and progress with no stage mean nothing. The request is a
    /// `POST` of the body with the key.
    func testTheStreamIsReadAsItsProgressThenTheFirstPicture() async throws {
        let host = "pictures-stream.test"
        let look = Data([1, 2, 3]).base64EncodedString()
        let drawn = Data("drawn".utf8)
        let stream =
            frame("image_generation.progress", #"{"stage":"queued","position":2}"#)
            + frame("image_generation.progress", #"{"stage":"loading"}"#)
            + frame("image_generation.progress", #"{"step":3}"#)
            + frame("image_generation.progress", #"{"stage":"sampling","step":3,"total":20,"frame_b64":"\#(look)"}"#)
            + frame("image_generation.partial_image", #"{"b64_json":"AAAA"}"#)
            + frame("image_generation.completed", #"{"b64_json":"\#(drawn.base64EncodedString())","size":"64x32"}"#)
            + frame("image_generation.completed", #"{"b64_json":"AAAA"}"#)
            + frame("error", #"{"error":{"message":"too late"}}"#)
        let read = await events(.init(body: stream, type: "text/event-stream"), at: host)
        XCTAssertEqual(
            read,
            [
                .progress(RedrawProgress(stage: "queued", position: 2)),
                .progress(RedrawProgress(stage: "loading")),
                .progress(RedrawProgress(stage: "sampling", step: 3, total: 20, frame: Data([1, 2, 3]))),
                .drawn(drawn),
            ])
        let request = try XCTUnwrap(ChatsHub.requests(at: host).first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/v1/images/generations")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody ?? request.bodyStreamData))
        XCTAssertEqual((sent as? [String: Any])?["image"] as? String, picture.base64EncodedString())
    }

    /// An `error` event ends the stream with the Mac's own words, and so
    /// does an answer that is not a 2xx, with its body's.
    func testAnErrorEventAndARefusalAreSaidInTheMacsWords() async {
        let inside =
            frame("image_generation.progress", #"{"stage":"loading"}"#)
            + frame(
                "error", #"{"error":{"message":"the image model ran out of memory","code":"image_generation_failed"}}"#)
            + frame("image_generation.completed", #"{"b64_json":"AAAA"}"#)
        let failed = await events(.init(body: inside, type: "text/event-stream"), at: "pictures-error.test")
        XCTAssertEqual(
            failed, [.progress(RedrawProgress(stage: "loading")), .failed("the image model ran out of memory")])
        let refusal = #"{"error":{"message":"the mask has no white in it","type":"invalid_request_error","code":"x"}}"#
        let refused = await events(.init(status: 400, body: refusal), at: "pictures-refused.test")
        XCTAssertEqual(refused, [.failed("the mask has no white in it")])
    }

    /// A stream that ends with neither a picture nor an error is a failure,
    /// and a picture that is not base64 is one too.
    func testAStreamThatEndsWithoutAPictureFails() async {
        let stream = frame("image_generation.progress", #"{"stage":"finishing"}"#)
        let ended = await events(.init(body: stream, type: "text/event-stream"), at: "pictures-ended.test")
        XCTAssertEqual(
            ended, [.progress(RedrawProgress(stage: "finishing")), .failed("The render ended without a picture.")])
        let unread = await events(
            .init(body: frame("image_generation.completed", #"{"b64_json":"**"}"#), type: "text/event-stream"),
            at: "pictures-unread.test")
        XCTAssertEqual(unread, [.failed("The picture that came back could not be read.")])
    }

    /// A reader that leaves closes the request, which is what stops the
    /// render on the Mac: the stream is still open there, with a step read
    /// and no picture yet.
    func testAReaderThatLeavesClosesTheRequest() async throws {
        let host = "pictures-left.test"
        let stream = frame("image_generation.progress", #"{"stage":"sampling","step":1,"total":20}"#)
        ChatsHub.serve(
            .init(body: stream, type: "text/event-stream", holds: true), at: "/v1/images/generations", on: host)
        let hub = ChatsHub.provider(at: host)
        let picture = picture
        let reader = Task { () -> RedrawEvent? in
            for await event in hub.redraw(PictureRedraw(prompt: "a fox", image: picture, strength: 0.4)) {
                return event
            }
            return nil
        }
        let first = await reader.value
        XCTAssertEqual(first, .progress(RedrawProgress(stage: "sampling", step: 1, total: 20)))
        for _ in 0..<200 where ChatsHub.stopped(at: host) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(ChatsHub.stopped(at: host), 1, "the request outlived its reader")
    }

    /// Each stage is said in words, with its place in line or its step when
    /// the Mac gave one, in the locale's digits.
    func testEachStageOfARedrawHasItsSentence() {
        let english = Locale(identifier: "en_US")
        func line(_ progress: RedrawProgress?) -> String { RedrawProgress.line(for: progress, in: english) }
        XCTAssertEqual(line(nil), "Loading the image model…")
        XCTAssertEqual(line(RedrawProgress(stage: "loading")), "Loading the image model…")
        XCTAssertEqual(line(RedrawProgress(stage: "queued", position: 2)), "Waiting for the GPU, place 2 in line…")
        XCTAssertEqual(line(RedrawProgress(stage: "queued")), "Waiting for the GPU…")
        XCTAssertEqual(line(RedrawProgress(stage: "sampling", step: 12, total: 20)), "Drawing, step 12 of 20…")
        XCTAssertEqual(line(RedrawProgress(stage: "sampling")), "Drawing…")
        XCTAssertEqual(line(RedrawProgress(stage: "decoding")), "Finishing the picture…")
        XCTAssertEqual(line(RedrawProgress(stage: "finishing")), "Finishing the picture…")
        XCTAssertEqual(
            RedrawProgress.line(
                for: RedrawProgress(stage: "sampling", step: 12, total: 20), in: Locale(identifier: "ar_EG")),
            "Drawing, step ١٢ of ٢٠…")
    }

    /// A kept picture is a `POST` of its two ids to the chat's `pictures`,
    /// answered with the row's images; a refusal is the Mac's error.
    func testAPictureIsKeptByItsTwoIDsAndARefusalIsTheMacsError() async throws {
        let host = "pictures-keep.test"
        let row =
            #"[{"id":"aa","mime":"image/png","width":64,"height":32},"#
            + #"{"id":"bb","mime":"image/png","width":64,"height":32}]"#
        ChatsHub.serve(.init(body: row), at: "/v1/chats/12/pictures", on: host)
        let refusal =
            #"{"error":{"message":"no such image","type":"invalid_request_error","#
            + #""code":"attachment_not_found"}}"#
        ChatsHub.serve(.init(status: 400, body: refusal), at: "/v1/chats/13/pictures", on: host)
        let hub = ChatsHub.provider(at: host)
        let images = try await hub.keepPicture(chatID: 12, KeptPicture(from: "aa", image: "bb"))
        XCTAssertEqual(images.map(\.id), ["aa", "bb"])
        let request = try XCTUnwrap(ChatsHub.requests(at: host).first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/v1/chats/12/pictures")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody ?? request.bodyStreamData))
        XCTAssertEqual(sent as? [String: String], ["from": "aa", "image": "bb"])
        do {
            _ = try await hub.keepPicture(chatID: 13, KeptPicture(from: "aa", image: "cc"))
            XCTFail("a refusal was taken as kept")
        } catch {
            XCTAssertEqual(error, .server(status: 400, code: "attachment_not_found", message: "no such image"))
        }
    }

    /// A picture's words are the `prompt` of the drawing tool's call its
    /// tool row answers, whether the arguments came as an object or as
    /// JSON text; another tool's image, a question's and a picture whose
    /// call has no words have none.
    func testADrawnPicturesWordsAreItsToolCallsPrompt() throws {
        func image(_ id: String) -> String { #"{"id":"\#(id)","mime":"image/png","width":64,"height":32}"# }
        func row(_ id: Int, _ role: String, _ rest: String = "") -> String {
            #"{"id":\#(id),"conversation_id":1,"role":"\#(role)","content":"","created_at":"a"\#(rest)}"#
        }
        let draw = "builtin:generate_image"
        let calls =
            #"{"id":"c1","name":"\#(draw)","arguments":{"prompt":" a red fox ","size":"64x32"}},"#
            + #"{"id":"c2","name":"\#(draw)","arguments":"{\"prompt\":\"a blue jay\"}"},"#
            + #"{"id":"c3","name":"builtin:read_file","arguments":{"prompt":"not a picture"}},"#
            + #"{"id":"c4","name":"\#(draw)","arguments":{"size":"64x32"}}"#
        let rows = [
            row(2, "user", #","images":[\#(image("question"))]"#),
            row(3, "assistant", #","metadata":{"tool_calls":[\#(calls)]}"#),
            row(4, "tool", #","metadata":{"tool_call_id":"c1"},"images":[\#(image("fox")),\#(image("fox-again"))]"#),
            row(5, "tool", #","metadata":{"tool_call_id":"c2"},"images":[\#(image("jay"))]"#),
            row(6, "tool", #","metadata":{"tool_call_id":"c3"},"images":[\#(image("chart"))]"#),
            row(7, "tool", #","metadata":{"tool_call_id":"c4"},"images":[\#(image("wordless"))]"#),
            row(8, "tool", #","images":[\#(image("unanswered"))]"#),
        ]
        let json =
            #"{"conversation":{"id":1,"title":"t","created_at":"a","updated_at":"b"},"messages":["#
            + rows.joined(separator: ",") + "]}"
        let chat = try JSONDecoder().decode(HubChatOpen.self, from: Data(json.utf8))
        XCTAssertEqual(chat.drawnPrompts, ["fox": "a red fox", "fox-again": "a red fox", "jay": "a blue jay"])
        XCTAssertEqual(chat.messages[2].metadata?.toolCallID, "c1")
    }

    /// A reply kept on this device knows its picture's words from the one
    /// call that drew; with none, with a draw that failed, or with two that
    /// drew, it knows none.
    func testAKeptReplyKnowsItsPicturesWordsFromTheOneCallThatDrew() {
        func call(_ id: String, _ result: String?, name: String = HubToolCall.drawingTool) -> ToolExchange {
            ToolExchange(callID: id, name: name, arguments: #"{"prompt":"a red fox in snow"}"#, result: result)
        }
        func reply(_ exchanges: [ToolExchange]) -> Message {
            Message(
                role: .assistant, content: "A fox.", createdAt: Date(timeIntervalSince1970: 0), exchanges: exchanges)
        }
        let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
        XCTAssertEqual(reply([call("a", drew)]).drawnPrompt, "a red fox in snow")
        XCTAssertEqual(reply([call("a", "image_generation_failed"), call("b", drew)]).drawnPrompt, "a red fox in snow")
        XCTAssertNil(reply([]).drawnPrompt)
        XCTAssertNil(reply([call("a", nil)]).drawnPrompt)
        XCTAssertNil(reply([call("a", "image_generation_failed")]).drawnPrompt)
        XCTAssertNil(reply([call("a", drew, name: "builtin:read_file")]).drawnPrompt)
        XCTAssertNil(reply([call("a", drew), call("b", drew)]).drawnPrompt)
    }
}
