import XCTest

@testable import GGChatCore

/// How gglib refuses an image, by the two routes a direct chat takes: the
/// chat route answers at once, and a run's `PUT` is taken and the run fails.
final class ImageRefusalTests: XCTestCase {
    /// The line under each image code, as `ProviderError.Code.hint` says it.
    static let hints: [ProviderError.Code: String] = [
        .modelCannotReadImages:
            "This model has no projector, so it cannot read images. Pick a model that can see, or link a projector "
            + "on the machine that serves it with \u{201C}gglib model update <model> --projector <file>\u{201D}.",
        .requestTooLarge:
            "The request is over the 32 MiB the server takes. Send fewer or smaller images, or start a new "
            + "conversation.",
        .imageTooLarge: "The image is over the 8 MiB the server takes for one image. Send a smaller one.",
        .unsupportedImage: "The server takes only PNG and JPEG images whose size it can read.",
        .attachmentNotFound: "The server no longer has an image this conversation names. Send the image again.",
        .requestImagesTooLarge:
            "The images in this conversation are over the 16 MiB one request to a model may carry. Start a new "
            + "conversation to send more.",
    ]

    static let cannotSee =
        "Model 'Qwen3-4B' cannot read images: it has no projector linked. Link one with "
        + "`gglib model update Qwen3-4B --projector <path>`, or name a model that has one."

    private let image = ImageContentWireTests.pngRef
    private var request: ChatRequest {
        ChatRequest(
            model: "Qwen3-4B",
            messages: [Message(role: .user, content: "what is this", createdAt: .distantPast, images: [image])],
            images: [image.id: ImageContentWireTests.png])
    }

    /// The six codes gglib's image input writes, spelt as
    /// `docs/error-codes.json` spells them, each a request to change, with
    /// a line that says what to change. A saved failure draws the same.
    func testEachImageCodeSaysWhatToChange() {
        XCTAssertEqual(
            Set(Self.hints.keys.map(\.rawValue)),
            [
                "model_cannot_read_images", "request_too_large", "image_too_large", "unsupported_image",
                "attachment_not_found", "request_images_too_large",
            ])
        for (code, hint) in Self.hints {
            XCTAssertEqual(code.whereToLook, .request, code.rawValue)
            XCTAssertEqual(code.hint, hint, code.rawValue)
            let saved = Failure(ProviderError.stream(code: code.rawValue, message: "m"))
            XCTAssertEqual(saved.hint, hint, code.rawValue)
        }
    }

    /// The chat route refuses an image for a model with no projector at
    /// once, with a 400 and the code, after the image was sent as a part.
    func testTheChatRouteRefusesAnImageAtOnceByName() async throws {
        let body =
            #"{"error":{"message":"\#(Self.cannotSee)","type":"invalid_request_error","#
            + #""code":"model_cannot_read_images"}}"#
        let events = try await chat(answering: 400, body, host: "blind.images.test")
        XCTAssertEqual(
            events, [.error(.server(status: 400, code: "model_cannot_read_images", message: Self.cannotSee))])
        XCTAssertEqual(
            events.first.flatMap { if case .error(let error) = $0 { error.hint } else { nil } },
            Self.hints[.modelCannotReadImages])
    }

    /// A body over gglib's limit is a 413 with `request_too_large`.
    func testABodyOverTheLimitIsRefusedAsTooLarge() async throws {
        let message = "Request body exceeds the 32 MiB limit."
        let body = #"{"error":{"message":"\#(message)","type":"invalid_request_error","code":"request_too_large"}}"#
        let events = try await chat(answering: 413, body, host: "large.images.test")
        XCTAssertEqual(events, [.error(.server(status: 413, code: "request_too_large", message: message))])
        XCTAssertEqual(
            ProviderError.server(status: 413, code: "request_too_large", message: message).hint,
            Self.hints[.requestTooLarge])
    }

    /// A run's `PUT` is the chat route's body, images included, and is
    /// taken: the refusal comes later, as the run's failure under the code.
    func testARunIsTakenThenFailsWithTheCode() async throws {
        let id = "6A1F0C2E-5B7D-4E39-9C08-3D2B1A4F5E60"
        let host = "blind.runs.test"
        var script = RunHub.Script(
            frames: [], ending: RunHub.report(id, "failed", lastSeq: 0, error: "model_cannot_read_images"))
        script.put = (201, RunHub.report(id, "queued", lastSeq: 0))
        RunHub.serve(script, at: host)
        let provider = RunHub.provider(at: host)
        let started = try await provider.startRun(id: id, request)
        guard case .started = started else { return XCTFail("the PUT was not taken: \(started)") }
        let put = try XCTUnwrap(RunHub.requests(at: host).first)
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(put.httpBody ?? put.bodyStreamData))
        let chat = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        XCTAssertEqual(sent as? NSDictionary, chat as? NSDictionary, "the run was not sent the chat route's body")
        XCTAssertTrue(
            try XCTUnwrap(String(data: try XCTUnwrap(put.httpBody ?? put.bodyStreamData), encoding: .utf8))
                .contains(#""type":"image_url""#), "the PUT carried no image")

        var events: [RunEvent] = []
        for await event in provider.runEvents(id: id, after: 0) { events.append(event) }
        guard case .ended(let info)? = events.last else { return XCTFail("the run did not end: \(events)") }
        XCTAssertEqual(info.status, .failed)
        XCTAssertEqual(info.error?.code, "model_cannot_read_images")
    }

    /// Every event a chat request to `host` yields, answered with `status`
    /// and `body`, and checked to have carried the image as a part.
    private func chat(answering status: Int, _ body: String, host: String) async throws -> [ChatEvent] {
        StubURLProtocol.register(
            host: host, path: "/v1/chat/completions", .init(status: status, chunks: [Data(body.utf8)]))
        let provider = OpenAICompatibleProvider(
            baseURL: try XCTUnwrap(URL(string: "http://\(host)/v1")), apiKey: nil,
            session: StubURLProtocol.makeSession(), log: NoopLogSink())
        var events: [ChatEvent] = []
        for await event in provider.stream(request) { events.append(event) }
        let post = try XCTUnwrap(StubURLProtocol.requests(host: host).first)
        let sent = String(decoding: try XCTUnwrap(post.httpBody ?? post.bodyStreamData), as: UTF8.self)
        XCTAssertTrue(sent.contains(#""type":"image_url""#), "the request carried no image")
        return events
    }
}
