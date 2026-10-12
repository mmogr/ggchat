import CoreGraphics
import GGChatCore
import XCTest

@testable import GGChatUI

/// The mask the Mac is sent: the picture's own size, opaque black where
/// the picture is kept and white where it was brushed, with a later stroke
/// that rubs out black again, and the strokes placed from the top left.
final class PictureMaskTests: XCTestCase {
    /// The red, green, blue and alpha of one pixel, counted from the top
    /// left, read by drawing the picture over a clear context: a pixel
    /// with no alpha of its own would stay clear.
    private func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel
    }

    private func mask(_ strokes: [MaskStroke], width: Int = 64, height: Int = 48) throws -> CGImage {
        GeneratedImages.decode(try XCTUnwrap(PictureMask.png(of: strokes, width: width, height: height)))
    }

    private let black: [UInt8] = [0, 0, 0, 255]
    private let white: [UInt8] = [255, 255, 255, 255]
    /// A pass of the brush along the top, left of the middle.
    private let top = MaskStroke(points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)], width: 8)

    /// The mask is the picture's size exactly, a PNG with no alpha, black
    /// and fully opaque wherever nothing was brushed, with no strokes too.
    func testTheMaskIsThePicturesSizeAndOpaqueBlackWhereNothingWasBrushed() throws {
        let data = try XCTUnwrap(PictureMask.png(of: [top], width: 64, height: 48))
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let size = try XCTUnwrap(PictureMask.size(of: data))
        XCTAssertEqual([size.width, size.height], [64, 48])
        let image = GeneratedImages.decode(data)
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))
        for (x, y) in [(0, 0), (63, 0), (0, 47), (63, 47), (32, 40)] {
            XCTAssertEqual(pixel(of: image, x: x, y: y), black, "(\(x), \(y))")
        }
        let empty = try mask([])
        XCTAssertEqual(pixel(of: empty, x: 20, y: 10), black)
        XCTAssertNil(PictureMask.png(of: [top], width: 0, height: 48))
    }

    /// A stroke is white where it went, counted from the picture's top
    /// left: the same place counted from the bottom is still black. Its
    /// ends are round and it is as wide as its brush.
    func testAStrokeIsWhiteWhereItWentFromTheTopLeft() throws {
        let image = try mask([top])
        XCTAssertEqual(pixel(of: image, x: 20, y: 10), white)
        XCTAssertEqual(pixel(of: image, x: 20, y: 37), black, "the mask is upside down")
        XCTAssertEqual(pixel(of: image, x: 20, y: 12), white)
        XCTAssertEqual(pixel(of: image, x: 20, y: 16), black)
        XCTAssertEqual(pixel(of: image, x: 32, y: 10), white, "the end is not round")
        XCTAssertEqual(pixel(of: image, x: 36, y: 10), black)
    }

    /// A later stroke that rubs out is black again where it crosses, and
    /// one before the paint takes nothing off: the strokes are in order.
    func testALaterRubOutIsBlackAgainAndAnEarlierOneIsNot() throws {
        let rub = MaskStroke(points: [CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 20)], width: 6, erases: true)
        let after = try mask([top, rub])
        XCTAssertEqual(pixel(of: after, x: 20, y: 10), black)
        XCTAssertEqual(pixel(of: after, x: 12, y: 10), white)
        XCTAssertEqual(pixel(of: after, x: 28, y: 10), white)
        let before = try mask([rub, top])
        XCTAssertEqual(pixel(of: before, x: 20, y: 10), white)
    }

    /// A touch that never moved paints a dot as wide as the brush.
    func testASinglePointPaintsADot() throws {
        let image = try mask([MaskStroke(points: [CGPoint(x: 40, y: 30)], width: 10)])
        XCTAssertEqual(pixel(of: image, x: 40, y: 30), white)
        XCTAssertEqual(pixel(of: image, x: 43, y: 30), white)
        XCTAssertEqual(pixel(of: image, x: 40, y: 27), white)
        XCTAssertEqual(pixel(of: image, x: 47, y: 30), black)
        XCTAssertEqual(pixel(of: image, x: 40, y: 37), black)
    }

    /// The picture is drawn as large as fits the space it has, in the
    /// middle, and the strokes are placed by the same box.
    func testThePictureIsFittedToItsSpaceInTheMiddle() {
        let natural = CGSize(width: 1024, height: 512)
        XCTAssertEqual(
            PictureCanvas.box(of: natural, in: CGSize(width: 300, height: 400)),
            CGRect(x: 0, y: 125, width: 300, height: 150))
        XCTAssertEqual(
            PictureCanvas.box(of: natural, in: CGSize(width: 400, height: 100)),
            CGRect(x: 100, y: 0, width: 200, height: 100))
        XCTAssertEqual(PictureCanvas.box(of: natural, in: .zero), .zero)
        XCTAssertEqual(PictureCanvas.box(of: .zero, in: CGSize(width: 300, height: 400)), .zero)
    }
}
