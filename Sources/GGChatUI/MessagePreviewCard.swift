import GGChatCore
import SwiftUI

/// What a long-pressed message lifts above its menu: a card of its role and
/// its opening blocks at their own size, never the whole row shrunk to fit.
/// The system scales a preview down until it fits the screen, and a long
/// reply's row, reasoning and all, came out as a strip of unreadable text.
/// The card is one width whatever the message, and no taller than
/// `maxHeight`, with the text fading out where it is cut. A message of only
/// images shows its first.
struct MessagePreviewCard: View {
    @Environment(AppModel.self) private var model
    let message: Message
    /// Whether the images are a Mac's chat's, read from it into memory.
    let imagesFromHub: Bool

    nonisolated static let width: CGFloat = 340
    nonisolated static let maxHeight: CGFloat = 420
    /// How far up from a cut edge the text fades.
    private static let fade: CGFloat = 48

    /// Whether the card's content is taller than the card.
    @State private var overflows = false

    var body: some View {
        let preview = MarkdownPreview(MarkdownBlocks.parse(message.content))
        VStack(alignment: .leading, spacing: 8) {
            RoleLabel(role: message.role)
            if preview.blocks.isEmpty, let image = message.images.first {
                ImageThumbnail(
                    picture: imagesFromHub ? model.hubThumbnail(of: image) : model.thumbnail(of: image),
                    side: 200)
            }
            MarkdownBlocksView(blocks: preview.blocks)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.height > Self.maxHeight - 32
        } action: {
            overflows = $0
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: Self.maxHeight, alignment: .top)
        .clipped()
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                if preview.isCut || overflows {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
        }
        .background(.background)
    }
}
