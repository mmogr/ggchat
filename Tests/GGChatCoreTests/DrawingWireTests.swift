import XCTest

@testable import GGChatCore

/// What gglib says about drawing, as this device reads it: the codes it
/// refuses with, and which of its models draw.
final class DrawingWireTests: XCTestCase {
    /// The line under each drawing code, as `ProviderError.Code.hint` says it.
    static let hints: [ProviderError.Code: String] = [
        .imageModelCannotChat:
            "This model draws pictures and cannot chat. Pick a chat model, and press Draw to ask it for a picture.",
        .drawingUnavailable:
            "The serving machine has nothing to draw with for this message. It needs an image model with all its "
            + "files, and a default one when it has several.",
        .invalidImageSize: "The image model does not draw that size. Ask for a size the server's sentence names.",
        .imageGenerationFailed:
            "The image model started the picture and failed. Ask again, or for another picture or size.",
        .imageRenderStalled: "The picture stopped making progress, so the image model was stopped. Ask again.",
        .imageRuntimeNotInstalled:
            "The serving machine has no image runtime. Install it there with \u{201C}gglib config sd install\u{201D}.",
        .imageModelIncomplete:
            "The image model is missing a file it needs. The server's sentence names it and the command that links "
            + "it on the serving machine.",
        .imageModelDoesNotFit:
            "The image model needs more memory than is free while another reply is being written there. Ask again "
            + "when that reply has ended.",
    ]

    /// The eight codes gglib's drawing writes, spelt as `docs/error-codes.json`
    /// spells them, each with a line of its own that a saved failure draws
    /// too, and the two a run can now end with, which name a side. Where
    /// each says to look is pinned, so a picture that stalled says to ask
    /// again and not to look at a machine.
    func testEachDrawingCodeSaysWhatToDo() {
        XCTAssertEqual(
            Set(Self.hints.keys.map(\.rawValue)),
            [
                "image_model_cannot_chat", "drawing_unavailable", "invalid_image_size", "image_generation_failed",
                "image_render_stalled", "image_runtime_not_installed", "image_model_incomplete",
                "image_model_does_not_fit",
            ])
        for (code, hint) in Self.hints {
            XCTAssertEqual(code.hint, hint, code.rawValue)
            let saved = Failure(ProviderError.stream(code: code.rawValue, message: "m"))
            XCTAssertEqual(saved.hint, hint, code.rawValue)
        }
        let sides: [ProviderError.Code: WhereToLook] = [
            .imageModelCannotChat: .request, .invalidImageSize: .request,
            .drawingUnavailable: .servingSide, .imageGenerationFailed: .servingSide,
            .imageRuntimeNotInstalled: .servingSide, .imageModelIncomplete: .servingSide,
            .imageRenderStalled: .waitAndRetry, .imageModelDoesNotFit: .waitAndRetry,
            .modelUnavailable: .servingSide, .unavailable: .waitAndRetry,
        ]
        for (code, side) in sides {
            XCTAssertEqual(code.whereToLook, side, code.rawValue)
        }
        XCTAssertEqual(ProviderError.Code(rawValue: "model_unavailable"), .modelUnavailable)
        XCTAssertEqual(ProviderError.Code(rawValue: "unavailable"), .unavailable)
        XCTAssertEqual(
            ProviderError.stream(code: "model_unavailable", message: "m").hint, WhereToLook.servingSide.hint)
        XCTAssertEqual(ProviderError.stream(code: "unavailable", message: "m").hint, WhereToLook.waitAndRetry.hint)
    }

    /// gglib's list names a model that draws with `image_generation` and one
    /// that serves embeddings with `embeddings`. Neither can chat; a model
    /// with other words, or none, can.
    func testTheModelListSaysWhichModelDrawsAndWhichCanChat() throws {
        let body = #"""
            {"object":"list","data":[
              {"id":"flux-dev","object":"model","capabilities":["image_generation"]},
              {"id":"bge-small","object":"model","capabilities":["embeddings"]},
              {"id":"qwen3-vl","object":"model","capabilities":["vision","reasoning"]},
              {"id":"plain","object":"model"}
            ]}
            """#
        let models = try JSONDecoder().decode(ModelsResponse.self, from: Data(body.utf8)).data
        XCTAssertEqual(models.map(\.generatesImages), [true, false, false, false])
        XCTAssertEqual(models.map(\.chats), [false, false, true, true])
    }
}
