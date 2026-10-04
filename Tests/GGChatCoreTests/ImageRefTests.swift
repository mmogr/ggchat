import XCTest

@testable import GGChatCore

/// What is known of an image without its bytes, read and worked out as
/// gglib reads and works it out.
final class ImageRefTests: XCTestCase {
    /// The id is the SHA-256 of the bytes in lowercase hex, as gglib names a
    /// stored image: the vector is gglib's own (`attachment_tests.rs`, from
    /// FIPS 180-2).
    func testTheIdIsTheSHA256OfTheBytesInLowercaseHex() {
        XCTAssertEqual(
            ImageRef.id(of: Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNotEqual(ImageRef.id(of: Data("abd".utf8)), ImageRef.id(of: Data("abc".utf8)))
    }

    /// The cost is gglib's `estimate_image_tokens`: one token a 32-pixel
    /// square touched, at least 1, at most 4096. Every value here is one
    /// gglib's own tests assert (`images_tests.rs`).
    func testTheTokenEstimateIsGGLibsRule() {
        let cases: [(size: (Int, Int), tokens: Int)] = [
            ((2560, 1440), 3600), ((980, 460), 465), ((32, 32), 1), ((33, 32), 2), ((32, 33), 2), ((1, 1), 1),
            ((0, 0), 1), ((8000, 8000), 4096), ((64 * 32, 64 * 32), 4096), ((64 * 32, 63 * 32), 4032),
            ((Int(UInt32.max), Int(UInt32.max)), 4096),
        ]
        for ((width, height), tokens) in cases {
            let image = ImageRef(id: "", mime: ImageRef.png, width: width, height: height)
            XCTAssertEqual(image.estimatedTokens, tokens, "\(width)x\(height)")
        }
        XCTAssertEqual(ImageRef(id: "", mime: ImageRef.png, width: .max, height: .max).estimatedTokens, 4096)
    }

    /// The shape is gglib's `AttachmentInfo`, key for key, both ways.
    func testItReadsAndWritesGGLibsAttachmentInfo() throws {
        let id = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let gglib = #"{"id":"\#(id)","mime":"image/png","width":2560,"height":1440,"image_tokens":3600}"#
        let image = try JSONDecoder().decode(ImageRef.self, from: Data(gglib.utf8))
        XCTAssertEqual(image, ImageRef(id: id, mime: "image/png", width: 2560, height: 1440))
        let written = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(image)) as? [String: Any]
        XCTAssertEqual(written?.keys.sorted(), ["height", "id", "mime", "width"])
        XCTAssertEqual(ImageRef.png, "image/png")
        XCTAssertEqual(ImageRef.jpeg, "image/jpeg")
    }

    /// gglib's model list says which model reads images with `vision`, and
    /// leaves `capabilities` out for a model with nothing to list. The
    /// fixture's `vision` row was written by hand from gglib's
    /// `capabilities_of`, not recorded.
    func testTheModelListSaysWhichModelReadsImages() throws {
        let models = try JSONDecoder().decode(ModelsResponse.self, from: try Fixtures.data("gglib-models.json")).data
        XCTAssertFalse(models.isEmpty)
        let seeing = try XCTUnwrap(models.first { $0.id == "Qwen3.8-27B" })
        XCTAssertEqual(seeing.capabilities, ["vision"])
        XCTAssertTrue(seeing.readsImages)
        let blind = try XCTUnwrap(models.first { $0.id == "Qwen3-4B" })
        XCTAssertNil(blind.capabilities)
        XCTAssertFalse(blind.readsImages)
        XCTAssertFalse(ModelInfo(id: "e", capabilities: ["embeddings"]).readsImages)
        XCTAssertTrue(ModelInfo(id: "both", capabilities: ["embeddings", "vision"]).readsImages)
    }
}
