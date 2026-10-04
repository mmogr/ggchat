import GGChatCore
import SwiftUI

/// The images a turn carries, in a row of small pictures: a stored turn's
/// read from this device's store, and a Mac's chat's read from the Mac by id
/// into memory as each is drawn. One is opened whole in a sheet, as the
/// chat's other sheets open. An image not to hand is drawn as a plain symbol.
struct MessageImages: View {
    @Environment(AppModel.self) private var model
    @State private var enlarged: ImageRef?
    let images: [ImageRef]
    let fromHub: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    Button {
                        enlarged = image
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
        .sheet(item: $enlarged) { image in
            EnlargedImage(image: image, fromHub: fromHub)
        }
    }
}

/// One image at its own size, fitted to the sheet.
private struct EnlargedImage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let image: ImageRef
    let fromHub: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let picture = fromHub ? model.hubPicture(of: image) : model.picture(of: image) {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView("This device does not have this image", systemImage: "photo")
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
    }
}
