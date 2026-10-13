import GGChatCore
import SwiftUI

/// The images a turn carries, in a row of small pictures: a stored turn's
/// read from this device's store, and a Mac's chat's read from the Mac by id
/// into memory as each is drawn. One is opened whole in a sheet the root
/// shows (`EnlargedImage`), so the sheet outlives a row that is drawn again
/// or scrolled away. An image not to hand is drawn as a plain symbol.
struct MessageImages: View {
    @Environment(AppModel.self) private var model
    let images: [ImageRef]
    let fromHub: Bool
    /// The reply that holds them, in a conversation kept on this device.
    var owner: UUID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    Button {
                        model.enlarged = EnlargedPicture(image: image, fromHub: fromHub, owner: owner)
                    } label: {
                        ImageThumbnail(
                            picture: fromHub ? model.hubThumbnail(of: image) : model.thumbnail(of: image), side: 120)
                    }
                    .task(id: image.id) {
                        if fromHub { await model.fetchHubImage(image) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Image")
                    .accessibilityHint("Opens it whole")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// One image at its own size, fitted to the sheet. On iOS a pinch or a
/// double tap brings it closer (`ZoomablePicture`). Held down, or
/// right-clicked, it offers its own bytes to share, and on iOS to save to
/// Photos; what came of a save is said under it. Under a picture the
/// drawing tool made, where its chat's Mac can draw, Fix or redo opens its
/// editor in the same sheet (`PictureEditor`). Which image, and the editor,
/// are the model's: nothing here is lost with a row.
struct EnlargedImage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shown: EnlargedPicture
    /// What came of saving it to Photos, once that was asked.
    @State private var saveOutcome: String?

    var body: some View {
        let (image, fromHub, owner) = (shown.image, shown.fromHub, shown.owner)
        let picture = fromHub ? model.hubPicture(of: image) : model.picture(of: image)
        NavigationStack {
            VStack(spacing: 12) {
                if let picture {
                    whole(picture)
                        .contextMenu { offers(for: picture) }
                        .accessibilityElement()
                        .accessibilityLabel("Image")
                        .accessibilityIdentifier("enlarged-image")
                    if let saveOutcome {
                        Text(saveOutcome)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("save-outcome")
                    }
                    if model.drawnPrompt(of: image, in: owner, fromHub: fromHub) != nil {
                        Button("Fix or redo", systemImage: "paintbrush.pointed") { model.editEnlargedPicture() }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Brush over a part to draw it again, or draw the whole picture again")
                            .accessibilityIdentifier("fix-or-redo")
                    }
                } else {
                    ContentUnavailableView("This device does not have this image", systemImage: "photo")
                }
            }
            .padding()
            .navigationDestination(
                isPresented: Binding {
                    model.pictureEditor != nil
                } set: {
                    if !$0 { model.closePictureEditor() }
                }
            ) {
                if let editing = model.pictureEditor {
                    PictureEditor(editing: editing, original: picture) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
    }

    @ViewBuilder
    private func whole(_ picture: CGImage) -> some View {
        #if os(iOS)
            ZoomablePicture(picture: picture)
        #else
            Image(decorative: picture, scale: 1)
                .resizable()
                .scaledToFit()
        #endif
    }

    /// What the picture offers when held down: its own bytes, shared or
    /// saved, and nothing while they are not to hand.
    @ViewBuilder
    private func offers(for picture: CGImage) -> some View {
        if let file = model.file(of: shown) {
            #if os(iOS)
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    Task { saveOutcome = await PhotoLibrary.add(file) }
                }
            #endif
            ShareLink(item: file, preview: SharePreview("Image", image: Image(decorative: picture, scale: 1)))
        }
    }
}
