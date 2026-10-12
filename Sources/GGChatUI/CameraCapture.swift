#if os(iOS)
    import SwiftUI
    import UIKit

    /// The system's camera, for one photo to go with a message. The photo is
    /// handed on as a JPEG, upright by its orientation tag, and is the
    /// draft's like any picked image: `ImageIntake.prepare` makes it ready,
    /// and nothing is added to the person's Photos.
    struct CameraCapture: UIViewControllerRepresentable {
        /// How hard the photo is compressed on its way to `ImageDownscale`,
        /// which writes it again: lightly, so it is not worn twice.
        static let quality = 0.95

        let take: (Data) -> Void
        @Environment(\.dismiss) private var dismiss

        /// Whether this device has a camera to offer. A simulator and a Mac
        /// have none, and are shown the photo picker alone.
        static var isOffered: Bool {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(take: take) { dismiss() }
        }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let camera = UIImagePickerController()
            camera.sourceType = .camera
            camera.delegate = context.coordinator
            return camera
        }

        func updateUIViewController(_ camera: UIImagePickerController, context: Context) {}

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            private let take: (Data) -> Void
            private let close: () -> Void

            init(take: @escaping (Data) -> Void, close: @escaping () -> Void) {
                self.take = take
                self.close = close
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let photo = info[.originalImage] as? UIImage,
                    let data = photo.jpegData(compressionQuality: CameraCapture.quality)
                {
                    take(data)
                }
                close()
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                close()
            }
        }
    }
#endif
