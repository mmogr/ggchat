import CoreGraphics
import Foundation
import GGChatCore
import ImageIO
import UniformTypeIdentifiers

/// An image ready to go with a turn: the bytes that will be sent, the
/// reference that names them, and a small picture of them to show.
nonisolated struct DraftImage: Identifiable, Sendable {
    let ref: ImageRef
    let data: Data
    let thumbnail: CGImage?

    var id: String { ref.id }
}

/// Why an image was not taken, as its own sentence. Never the bytes.
nonisolated enum ImageRefusal: Error, Equatable, LocalizedError {
    case unreadable
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: "This app could not read that as an image."
        case .tooLarge: "That image is over 8 MiB even made smaller, so it cannot be sent."
        }
    }
}

/// The one way an image becomes what a turn sends, whether it was picked,
/// pasted or dropped: any image ImageIO reads (HEIC, PNG, JPEG, …) is turned
/// upright by its EXIF orientation, made at most 2560 pixels on its long
/// side, and written again with nothing of the original's metadata, its
/// location included. A PNG stays a PNG while it fits gglib's limit for one
/// image; anything else, or a PNG that does not fit, is a JPEG.
///
/// 8 MiB is gglib's limit for one image (`MAX_IMAGE_BYTES`,
/// `gglib-core/src/request_pipeline/images.rs`), and 2560 pixels is the long
/// edge of the screenshot its token estimate was measured on. Both are
/// arguments so a test can reach the JPEG and the refusal with small
/// pictures.
nonisolated struct ImageDownscale: Sendable {
    /// How hard a photo is compressed when it is written as a JPEG.
    static let jpegQuality = 0.85

    var longEdge = 2560
    var maxBytes = 8 << 20

    /// The image `data` holds, ready to send, or why it cannot be.
    func prepare(_ data: Data) throws(ImageRefusal) -> DraftImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
            let image = Self.upright(source, longEdge: min(max(width, height), longEdge))
        else { throw .unreadable }
        let isPNG = CGImageSourceGetType(source).flatMap { UTType($0 as String) } == .png
        if isPNG, let png = Self.encode(image, as: .png), png.count <= maxBytes {
            return Self.draft(png, of: image, mime: ImageRef.png)
        }
        guard let jpeg = Self.encode(image, as: .jpeg) else { throw .unreadable }
        guard jpeg.count <= maxBytes else { throw .tooLarge }
        return Self.draft(jpeg, of: image, mime: ImageRef.jpeg)
    }

    /// A small upright picture of the image `data` holds, for a strip or a
    /// row, or nil when it cannot be read.
    static func thumbnail(of data: Data, longEdge: Int = 240) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { upright($0, longEdge: longEdge) }
    }

    /// The first image in `source`, turned by its orientation and no longer
    /// than `longEdge` on its long side. ImageIO never makes it larger than
    /// the original.
    private static func upright(_ source: CGImageSource, longEdge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image alone: a `CGImage` carries no metadata, and none is added.
    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func draft(_ data: Data, of image: CGImage, mime: String) -> DraftImage {
        DraftImage(
            ref: ImageRef(id: ImageRef.id(of: data), mime: mime, width: image.width, height: image.height),
            data: data, thumbnail: thumbnail(of: data))
    }
}
