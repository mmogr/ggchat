import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The ways an image reaches a draft, for either composer: the photo picker
/// and, on iOS, a paste button here; a paste into the field on macOS and a
/// drop with `pastesImages` and `dropsImages`. Each hands on the bytes it
/// got, and `ImageIntake.prepare` makes every one ready the one way.
struct AddImageButtons: View {
    /// Off while a reply is being written.
    let disabled: Bool
    /// Why no image can be added to this draft, when none can.
    let refusal: String?
    let take: ([Data]) -> Void
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        // Both are grey circles: the same kind of control, plainly on, and
        // dimmed by the system when off. Send stays the one prominent action.
        PhotosPicker(selection: $picked, matching: .images) {
            Image(systemName: "photo.badge.plus")
                .font(.body)
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(.gray)
        .disabled(disabled || refusal != nil)
        .help(refusal ?? "Add an image")
        .accessibilityLabel("Add an image")
        .accessibilityHint(refusal ?? "")
        .accessibilityIdentifier("add-image")
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { take(await Self.load(items)) }
        }
        #if os(iOS)
            // iOS 26 has no paste destination for a view, and a text field
            // pastes text alone, so an image is pasted here.
            PasteButton(payloadType: ImageFile.self) { files in take(files.map(\.data)) }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .tint(.gray)
                .disabled(disabled || refusal != nil)
                .accessibilityIdentifier("paste-image")
        #endif
    }

    private static func load(_ items: [PhotosPickerItem]) async -> [Data] {
        var files: [Data] = []
        for item in items {
            if let file = try? await item.loadTransferable(type: ImageFile.self) { files.append(file.data) }
        }
        return files
    }
}

extension View {
    /// On macOS, an image pasted while this view has focus is handed to
    /// `take`; on iOS, `AddImageButtons` pastes.
    func pastesImages(_ take: @escaping ([Data]) -> Void) -> some View {
        #if os(macOS)
            onPasteCommand(of: ImageFile.pasted) { providers in
                Task {
                    var files: [Data] = []
                    for provider in providers {
                        if let data = await ImageFile.data(from: provider) { files.append(data) }
                    }
                    take(files)
                }
            }
        #else
            self
        #endif
    }

    /// An image dropped on this view is handed to `take`.
    func dropsImages(_ take: @escaping ([Data]) -> Void) -> some View {
        dropDestination(for: ImageFile.self) { files, _ in
            take(files.map(\.data))
            return !files.isEmpty
        }
    }
}

/// Making images ready for a draft.
nonisolated enum ImageIntake {
    /// Each of `files` through `ImageDownscale`, off the main actor, in the
    /// order given: the image ready to send, or why it cannot be.
    static func prepare(_ files: [Data]) async -> [Result<DraftImage, ImageRefusal>] {
        await Task.detached(priority: .userInitiated) {
            files.map { data in Result { () throws(ImageRefusal) in try ImageDownscale().prepare(data) } }
        }.value
    }
}

/// Any image, as the bytes it arrives in, from a paste, a drop or the photo
/// picker. `ImageDownscale` reads whichever kind it is.
nonisolated struct ImageFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { ImageFile(data: $0) }
    }

    #if os(macOS)
        /// What a paste is read for.
        static let pasted: [UTType] = [.image]

        /// The first image the provider holds, as bytes.
        @MainActor static func data(from provider: NSItemProvider) async -> Data? {
            guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) else {
                return nil
            }
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
            }
        }
    #endif
}
