import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pictures drawn for a test with Core Graphics and written with ImageIO,
/// so no test reads a file from disk or a photo library.
enum GeneratedImages {
    /// A colour as 8-bit red, green and blue.
    struct RGB: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }

    static let red = RGB(red: 255, green: 0, blue: 0)
    static let blue = RGB(red: 0, green: 0, blue: 255)

    /// `width` by `height`, its left half `left` and its right half `right`.
    /// With `noise`, every pixel is moved a little at random, which a PNG
    /// cannot compress and a JPEG can.
    static func halves(
        width: Int, height: Int, left: RGB = red, right: RGB = blue, noise: Bool = false
    ) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var generator = SystemRandomNumberGenerator()
        for row in 0..<height {
            for column in 0..<width {
                let colour = column < width / 2 ? left : right
                let jitter = noise ? Int.random(in: -24...24, using: &generator) : 0
                let at = (row * width + column) * 4
                pixels[at] = clamp(Int(colour.red) + jitter)
                pixels[at + 1] = clamp(Int(colour.green) + jitter)
                pixels[at + 2] = clamp(Int(colour.blue) + jitter)
            }
        }
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }

    /// `image` written as `type`, with `properties` as its metadata.
    static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination), "ImageIO did not write the test's image")
        return data as Data
    }

    /// The metadata ImageIO reads from `data`.
    static func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    /// `data` decoded as it is stored, with no orientation applied.
    static func decode(_ data: Data) -> CGImage {
        CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    }

    /// The colour of one pixel, counted from the top left.
    static func colour(of image: CGImage, x: Int, y: Int) -> RGB {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Core Graphics counts up from the bottom: the pixel wanted is moved
        // onto the context's one.
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return RGB(red: pixel[0], green: pixel[1], blue: pixel[2])
    }

    private static func clamp(_ value: Int) -> UInt8 {
        UInt8(min(max(value, 0), 255))
    }
}
