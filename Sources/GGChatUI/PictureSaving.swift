import CoreTransferable
import Foundation
import GGChatCore
import UniformTypeIdentifiers

#if os(iOS)
    import Photos
#endif

/// A picture as the bytes its chat keeps, to share or save: the same bytes,
/// under the kind its reference names, and never the picture drawn on screen
/// written out again.
nonisolated struct PictureFile: Transferable, Equatable {
    let data: Data
    let mime: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .exportingCondition { $0.mime == ImageRef.png }
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
            .exportingCondition { $0.mime != ImageRef.png }
    }
}

extension AppModel {
    /// The picture opened whole, as its bytes: a Mac's chat's from memory, a
    /// conversation kept here's from this device's store, and nil when they
    /// are not to hand.
    func file(of shown: EnlargedPicture) -> PictureFile? {
        let data = shown.fromHub ? hubImages.data(shown.image.id) : (try? store.loadImage(id: shown.image.id))
        return data.map { PictureFile(data: $0, mime: shown.image.mime) }
    }
}

#if os(iOS)
    /// Adding a picture to the person's Photos. Asked for leave to add and
    /// nothing more: the app never reads the library.
    nonisolated enum PhotoLibrary {
        static let saved = "Saved to Photos"
        static let refused = "ggchat is not allowed to add to Photos. Allow it in Settings."
        static let failed = "The picture could not be saved to Photos."

        /// Adds `file` as a photo, asking for leave the first time, and
        /// answers what to say of it.
        static func add(_ file: PictureFile) async -> String {
            switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
            case .authorized, .limited: break
            default: return refused
            }
            let data = file.data
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
                return saved
            } catch {
                return failed
            }
        }
    }
#endif
