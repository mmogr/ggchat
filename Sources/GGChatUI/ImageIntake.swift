import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The ways an image reaches a draft, for either composer: the photo picker
/// and, on iOS, the camera and the pasteboard, all behind the one button
/// here; a paste into the field on macOS and a drop with `pastesImages` and
/// `dropsImages`. Each hands on the bytes it got, and `ImageIntake.prepare`
/// makes every one ready the one way.
///
/// On iOS the one button opens a menu: the library, a new photo where there
/// is a camera, and a paste of the image on the pasteboard, so the
/// composer's toolbar is no wider for any of them. On macOS it opens the
/// photo picker as it always did.
struct AddImageButtons: View {
    /// Off while a reply is being written.
    let disabled: Bool
    /// Why no image can be added to this draft, when none can.
    let refusal: String?
    let take: ([Data]) -> Void
    @State private var picked: [PhotosPickerItem] = []
    #if os(iOS)
        /// Set by a composer that is to begin on the camera, and put back
        /// once it has been opened or could not be.
        var opensCamera: Binding<Bool> = .constant(false)
        @State private var pickingFromLibrary = false
        @State private var takingPhoto = false
    #endif

    var body: some View {
        // A grey circle: plainly on, and dimmed by the system when off. Send
        // stays the one prominent action.
        add
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
                .photosPicker(isPresented: $pickingFromLibrary, selection: $picked, matching: .images)
                .onChange(of: opensCamera.wrappedValue, initial: true) { _, asked in
                    guard asked else { return }
                    opensCamera.wrappedValue = false
                    takingPhoto = CameraCapture.isOffered && !disabled && refusal == nil
                }
                .fullScreenCover(isPresented: $takingPhoto) {
                    CameraCapture { take([$0]) }
                    .ignoresSafeArea()
                }
            #endif
    }

    /// On iOS, the menu. iOS 26 has no paste destination for a view, and a
    /// text field pastes text alone, so the pasteboard's image is a row of
    /// it; one with no image on the pasteboard does nothing, and asks for
    /// nothing. On macOS, the photo picker.
    @ViewBuilder
    private var add: some View {
        #if os(iOS)
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { pickingFromLibrary = true }
                if CameraCapture.isOffered {
                    Button("Take Photo", systemImage: "camera") { takingPhoto = true }
                }
                Button("Paste Image", systemImage: "doc.on.clipboard") { Task { take(await ImageFile.pasted()) } }
                    .accessibilityIdentifier("paste-image")
            } label: {
                symbol
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
        #else
            PhotosPicker(selection: $picked, matching: .images) { symbol }
        #endif
    }

    nonisolated private var symbol: some View {
        Image(systemName: "photo.badge.plus")
            .font(.body)
            .frame(minWidth: 28, minHeight: 28)
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
    /// `take`; on iOS, `AddImageButtons` pastes from its menu.
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
    #else
        /// The images on the pasteboard, as the bytes they were put there
        /// as. The pasteboard is read only once it says it holds an image,
        /// so a paste of nothing asks the system for nothing.
        @MainActor static func pasted() async -> [Data] {
            let pasteboard = UIPasteboard.general
            guard pasteboard.hasImages else { return [] }
            var files: [Data] = []
            for provider in pasteboard.itemProviders {
                if let bytes = await ImageFile.data(from: provider) { files.append(bytes) }
            }
            return files
        }
    #endif

    /// The first image the provider holds, as bytes.
    @MainActor static func data(from provider: NSItemProvider) async -> Data? {
        guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
    }
}
