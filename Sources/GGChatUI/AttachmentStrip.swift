import GGChatCore
import SwiftUI

/// The images a draft carries, in a row above its field: each a small
/// picture, what gglib estimates it costs in prompt tokens, and a way to
/// take it out. Stock views only, no glass: it sits inside a composer's.
struct AttachmentStrip: View {
    let images: [DraftImage]
    /// Whether an image is still being made ready to join them.
    let preparing: Bool
    let remove: (DraftImage) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(images) { image in
                    tile(image)
                }
                if preparing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("Making an image ready")
                }
            }
            .padding(.top, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func tile(_ image: DraftImage) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ImageThumbnail(picture: image.thumbnail, side: 64)
                Button {
                    remove(image)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove image")
            }
            Text(AttachmentStrip.cost(of: image.ref))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image, \(AttachmentStrip.cost(of: image.ref))")
    }

    /// "~3600 tokens": gglib's estimate for the image, `ImageRef.estimatedTokens`.
    static func cost(of image: ImageRef) -> String {
        "~\(image.estimatedTokens) tokens"
    }
}

/// A small picture, cropped to fill a rounded square `side` points across,
/// or a plain symbol when there is none to show.
struct ImageThumbnail: View {
    let picture: CGImage?
    let side: CGFloat

    var body: some View {
        Group {
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 10))
    }
}
