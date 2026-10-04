import CoreGraphics
import Foundation
import GGChatCore
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import GGChatUI

/// Every image a turn sends goes through one downscale: upright, no longer
/// than gglib reads on its long edge, none of the original's metadata, a PNG
/// while one fits and a JPEG otherwise, refused when even that is over
/// gglib's limit for one image, and named by the hash of what is sent.
final class ImageDownscaleTests: XCTestCase {
    private typealias Images = GeneratedImages

    /// A photo taken on its side is stored sideways with EXIF orientation 6,
    /// "turn me a quarter clockwise". What is sent is turned already: the
    /// stored left half, red, is the top.
    func testAnImageIsTurnedUprightByItsOrientation() throws {
        let sideways = Images.encode(
            Images.halves(width: 40, height: 20), as: .jpeg, properties: [kCGImagePropertyOrientation: 6])
        XCTAssertEqual(Images.properties(of: sideways)[kCGImagePropertyOrientation] as? Int, 6)

        let image = try ImageDownscale().prepare(sideways)

        XCTAssertEqual([image.ref.width, image.ref.height], [20, 40])
        let sent = Images.decode(image.data)
        XCTAssertEqual([sent.width, sent.height], [20, 40], "the bytes are not the turned picture")
        let top = Images.colour(of: sent, x: 10, y: 3)
        let bottom = Images.colour(of: sent, x: 10, y: 36)
        XCTAssertGreaterThan(top.red, 200, "the top is not the stored left half: \(top)")
        XCTAssertLessThan(top.blue, 60, "the top is not the stored left half: \(top)")
        XCTAssertGreaterThan(bottom.blue, 200, "the bottom is not the stored right half: \(bottom)")
        XCTAssertLessThan(bottom.red, 60, "the bottom is not the stored right half: \(bottom)")
    }

    /// 2560 pixels on the long edge at most, the shape kept, and a smaller
    /// image is sent at its own size rather than made larger.
    func testTheLongEdgeIsAtMost2560AndASmallImageIsNotMadeLarger() throws {
        let wide = try ImageDownscale().prepare(Images.encode(Images.halves(width: 3000, height: 1500), as: .png))
        XCTAssertEqual([wide.ref.width, wide.ref.height], [2560, 1280])
        let tall = try ImageDownscale().prepare(Images.encode(Images.halves(width: 1000, height: 2600), as: .jpeg))
        XCTAssertEqual(tall.ref.height, 2560)
        XCTAssertEqual(Double(tall.ref.width), 2560.0 * 1000 / 2600, accuracy: 1)

        let small = try ImageDownscale().prepare(Images.encode(Images.halves(width: 100, height: 50), as: .png))
        XCTAssertEqual([small.ref.width, small.ref.height], [100, 50])
        let sent = Images.decode(small.data)
        XCTAssertEqual([sent.width, sent.height], [100, 50])
    }

    /// A PNG stays a PNG while it fits; a JPEG is a JPEG; a PNG that does
    /// not fit is sent as a JPEG that does; and one that does not fit even
    /// as a JPEG is refused with a sentence. So is what is not an image.
    func testAPNGStaysAPNGWhileItFitsAndOtherwiseIsAJPEG() throws {
        XCTAssertEqual(ImageDownscale().maxBytes, 8 << 20, "not gglib's MAX_IMAGE_BYTES (images.rs)")
        XCTAssertEqual(ImageDownscale.jpegQuality, 0.85)
        let noisy = Images.encode(Images.halves(width: 300, height: 300, noise: true), as: .png)
        let png = try ImageDownscale().prepare(noisy)
        XCTAssertEqual(png.ref.mime, ImageRef.png)
        XCTAssertEqual(UTType(Self.type(of: png.data)), .png)

        let fromJPEG = try ImageDownscale().prepare(Images.encode(Images.halves(width: 30, height: 30), as: .jpeg))
        XCTAssertEqual(fromJPEG.ref.mime, ImageRef.jpeg)
        XCTAssertEqual(UTType(Self.type(of: fromJPEG.data)), .jpeg)

        let limit = png.data.count - 1
        let squeezed = try ImageDownscale(maxBytes: limit).prepare(noisy)
        XCTAssertEqual(squeezed.ref.mime, ImageRef.jpeg)
        XCTAssertEqual(UTType(Self.type(of: squeezed.data)), .jpeg)
        XCTAssertLessThanOrEqual(squeezed.data.count, limit)

        XCTAssertThrowsError(try ImageDownscale(maxBytes: 100).prepare(noisy)) { error in
            XCTAssertEqual(error as? ImageRefusal, .tooLarge)
        }
        XCTAssertEqual(
            ImageRefusal.tooLarge.errorDescription, "That image is over 8 MiB even made smaller, so it cannot be sent."
        )
        XCTAssertThrowsError(try ImageDownscale().prepare(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? ImageRefusal, .unreadable)
        }
    }

    /// A photo's location, its camera and its date stay on this device: what
    /// is sent carries none of them, and no orientation left to apply.
    func testNothingOfTheOriginalsMetadataIsSent() throws {
        let located = Images.encode(
            Images.halves(width: 40, height: 20), as: .jpeg,
            properties: [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W",
                ],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Camera Maker"],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:04 09:30:00"],
            ])
        let before = Images.properties(of: located)
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary], "the test's photo has no location to lose")
        XCTAssertNotNil(before[kCGImagePropertyTIFFDictionary])

        let sent = try ImageDownscale().prepare(located)
        XCTAssertEqual(sent.ref.mime, ImageRef.jpeg)
        let after = Images.properties(of: sent.data)
        XCTAssertNil(after[kCGImagePropertyGPSDictionary], "the location was sent")
        let tiff = after[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake], "the camera was sent")
        let exif = after[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal], "the date was sent")
        XCTAssertEqual(after[kCGImagePropertyOrientation] as? Int ?? 1, 1, "an orientation is left to apply")
        let png = try ImageDownscale().prepare(
            Images.encode(
                Images.halves(width: 20, height: 20), as: .png,
                properties: [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5]]))
        XCTAssertEqual(png.ref.mime, ImageRef.png)
        XCTAssertNil(Images.properties(of: png.data)[kCGImagePropertyGPSDictionary], "the location was sent")
    }

    /// The reference names exactly the bytes sent: their SHA-256, their
    /// type, and the size they decode to. A small picture comes with them.
    func testTheIdIsTheSHA256OfTheBytesSent() throws {
        let image = try ImageDownscale().prepare(Images.encode(Images.halves(width: 64, height: 48), as: .jpeg))
        XCTAssertEqual(image.ref.id, ImageRef.id(of: image.data))
        XCTAssertEqual(image.id, image.ref.id)
        let sent = Images.decode(image.data)
        XCTAssertEqual([image.ref.width, image.ref.height], [sent.width, sent.height])
        XCTAssertEqual(image.ref.mime, ImageRef.jpeg)
        let thumbnail = try XCTUnwrap(image.thumbnail)
        XCTAssertEqual([thumbnail.width, thumbnail.height], [64, 48])
    }

    private static func type(of data: Data) -> String {
        (CGImageSourceGetType(CGImageSourceCreateWithData(data as CFData, nil)!) as String?) ?? ""
    }
}
