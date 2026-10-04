import XCTest

@testable import GGChatCore

/// A message's content on the OpenAI wire: a bare string with no images, as
/// it always was, and an array of parts with them.
final class ImageContentWireTests: XCTestCase {
    static let png = Data("PNGBYTES".utf8)
    static let jpeg = Data([0xFF, 0xD8, 0xFF])
    static let pngRef = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 2560, height: 1440)
    static let jpegRef = ImageRef(id: ImageRef.id(of: jpeg), mime: ImageRef.jpeg, width: 640, height: 480)

    /// Encoded with its keys sorted, since the encoder the app uses writes
    /// them in no fixed order, before this change and after.
    private func sortedJSON(_ request: ChatRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(ChatCompletionRequest(request)), as: UTF8.self)
    }

    /// A request with no images is the bytes it was before images existed:
    /// every turn's content a bare string, a slash escaped as the encoder
    /// always escaped it. The expected text was taken from the encoding
    /// before this change.
    func testARequestWithNoImagesIsTheSameBytesAsBefore() throws {
        let request = ChatRequest(
            model: "m",
            messages: [
                Message(role: .system, content: "Be brief.", createdAt: .distantPast),
                Message(role: .user, content: "hi / there", createdAt: .distantPast),
            ],
            returnProgress: true)
        XCTAssertEqual(
            try sortedJSON(request),
            #"{"messages":[{"content":"Be brief.","role":"system"},{"content":"hi \/ there","role":"user"}],"#
                + #""model":"m","return_progress":true,"stream":true,"stream_options":{"include_usage":true}}"#)
    }

    /// A turn with images is a list: its text first, then one `image_url`
    /// part per image, in the turn's order, each a `data:` URL of its type.
    /// A turn beside it with none is still a bare string.
    func testATurnWithImagesIsItsTextThenEachImageInOrder() throws {
        let request = ChatRequest(
            model: "m",
            messages: [
                Message(role: .user, content: "before", createdAt: .distantPast),
                Message(
                    role: .user, content: "what are these", createdAt: .distantPast,
                    images: [Self.jpegRef, Self.pngRef]),
            ],
            images: [Self.pngRef.id: Self.png, Self.jpegRef.id: Self.jpeg])
        XCTAssertEqual(
            try sortedJSON(request),
            #"{"messages":[{"content":"before","role":"user"},{"content":["#
                + #"{"text":"what are these","type":"text"},"#
                + #"{"image_url":{"url":"data:image\/jpeg;base64,\/9j\/"},"type":"image_url"},"#
                + #"{"image_url":{"url":"data:image\/png;base64,UE5HQllURVM="},"type":"image_url"}],"#
                + #""role":"user"}],"model":"m","stream":true,"stream_options":{"include_usage":true}}"#)
    }

    /// A turn of images alone has no text part, not an empty one, and the
    /// same image twice is sent twice.
    func testATurnOfImagesAloneHasNoTextPart() throws {
        let request = ChatRequest(
            model: "m",
            messages: [
                Message(role: .user, content: "", createdAt: .distantPast, images: [Self.pngRef, Self.pngRef])
            ],
            images: [Self.pngRef.id: Self.png])
        let wire = try ChatCompletionRequest(request)
        let part = ChatCompletionRequest.Part.imageURL("data:image/png;base64,UE5HQllURVM=")
        XCTAssertEqual(wire.messages.map(\.content), [.parts([part, part])])
    }

    /// A turn naming an image the request holds no bytes for is not sent
    /// without it, and what is said names the id and no image.
    func testATurnNamingAnImageWithNoBytesIsNotEncoded() throws {
        let request = ChatRequest(
            model: "m",
            messages: [Message(role: .user, content: "this", createdAt: .distantPast, images: [Self.pngRef])],
            images: [Self.jpegRef.id: Self.jpeg])
        XCTAssertThrowsError(try ChatCompletionRequest(request)) { error in
            let missing = error as? ChatCompletionRequest.MissingImage
            XCTAssertEqual(missing?.id, Self.pngRef.id)
            XCTAssertEqual(
                missing?.description, "an image the request names has no bytes (\(Self.pngRef.id))")
        }
        let told = ChatRequest(
            model: "m", messages: request.messages, images: [Self.pngRef.id: Self.png])
        XCTAssertNoThrow(try ChatCompletionRequest(told), "the same turn with its bytes is sent")
    }
}
