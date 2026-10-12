import CoreGraphics
import Foundation
import GGChatCore
import ImageIO

/// The mask a person brushes over a picture, as the Mac reads it: a PNG the
/// picture's own size in pixels, black where the picture is kept and white
/// where it is drawn again.
///
/// It is painted on black and has no alpha: the Mac reads a mask's colour
/// and not its alpha, so a clear pixel would read as whatever colour lies
/// under it. The strokes are in the picture's pixels from its top left, and
/// Core Graphics counts up from the bottom, so the context is turned over
/// before anything is painted.
nonisolated enum PictureMask {
    /// The mask of `strokes` for a picture `width` by `height`, as a PNG:
    /// black all over, then each stroke in order, white for one that paints
    /// and black for one that rubs out. Nil when there is no such picture.
    static func png(of strokes: [MaskStroke], width: Int, height: Int) -> Data? {
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        // The Mac reads a pixel as white from mid-grey, so an edge is left
        // hard: a blend would put the line a pixel either way.
        context.setShouldAntialias(false)
        for stroke in strokes {
            paint(stroke, in: context, as: CGColor(gray: stroke.erases ? 0 : 1, alpha: 1))
        }
        return context.makeImage().flatMap { ImageDownscale.encode($0, as: .png) }
    }

    /// One stroke in `colour`: a round-ended line through its points, and a
    /// dot for a single point.
    static func paint(_ stroke: MaskStroke, in context: CGContext, as colour: CGColor) {
        guard let first = stroke.points.first else { return }
        if stroke.points.count == 1 {
            let half = stroke.width / 2
            context.setFillColor(colour)
            context.fillEllipse(
                in: CGRect(x: first.x - half, y: first.y - half, width: stroke.width, height: stroke.width))
            return
        }
        context.setStrokeColor(colour)
        context.setLineWidth(stroke.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: first)
        for point in stroke.points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }

    /// The size in pixels of the image `data` holds, as it is stored.
    static func size(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        return (width, height)
    }
}
