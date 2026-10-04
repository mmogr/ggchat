import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    // An id is compared with the one gglib computes for the same bytes, so
    // there is no second way to work it out. See `ImageRef.id(of:)`.
    #error("ImageRef.id(of:) needs CryptoKit.")
#endif

/// An image a message carries, by reference: what is known of it without
/// its bytes. The bytes are kept on this device under ``id`` and read only
/// when a request is built, so a ``Message`` stays as cheap to compare and
/// to keep as its text.
///
/// The shape of gglib's `AttachmentInfo` (`gglib-core/src/domain/attachment.rs`),
/// key for key, so the same value reads a gglib answer that names an image.
public struct ImageRef: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// The SHA-256 of the bytes sent, in lowercase hex: ``id(of:)``.
    public var id: String
    /// ``png`` or ``jpeg``.
    public var mime: String
    /// Its width in pixels.
    public var width: Int
    /// Its height in pixels.
    public var height: Int

    public init(id: String, mime: String, width: Int, height: Int) {
        self.id = id
        self.mime = mime
        self.width = width
        self.height = height
    }

    /// The type of a PNG.
    public static let png = "image/png"
    /// The type of a JPEG.
    public static let jpeg = "image/jpeg"

    /// The id of `data`: its SHA-256 in lowercase hex, as gglib names a
    /// stored image (`AttachmentId::of`), so the same bytes are one image on
    /// both sides.
    public static func id(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The prompt tokens this image is estimated to take, by gglib's rule
    /// (`estimate_image_tokens`, `gglib-core/src/request_pipeline/images.rs`):
    /// one for each 32-pixel square it touches, at least 1 and at most 4096,
    /// the model family's own cap.
    public var estimatedTokens: Int {
        let cap = 4096
        func squares(_ pixels: Int) -> Int {
            let pixels = max(pixels, 0)
            return pixels / 32 + (pixels.isMultiple(of: 32) ? 0 : 1)
        }
        let (tokens, overflow) = squares(width).multipliedReportingOverflow(by: squares(height))
        return overflow ? cap : min(max(tokens, 1), cap)
    }
}

extension ModelInfo {
    /// Whether gglib's model list says this model reads images: `vision` in
    /// its `capabilities`, which gglib writes for a model linked to a
    /// projector. Another server never writes it, so false here says nothing
    /// about a model that is not gglib's.
    public var readsImages: Bool {
        capabilities?.contains("vision") == true
    }
}
