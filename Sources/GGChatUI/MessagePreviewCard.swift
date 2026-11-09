import GGChatCore
import SwiftUI

/// What a long-pressed message lifts above its menu: a card of its role and
/// its opening blocks at their own size, never the whole row shrunk to fit.
/// The system scales a preview down until it fits the screen, and a long
/// reply's row, reasoning and all, came out as a strip of unreadable text.
/// The card is one width whatever the message, and no taller than
/// `maxHeight`, with the text fading out where it is cut. A message of only
/// images shows its first.
///
/// The card reads nothing from the environment's model: the system draws a
/// preview in a hosting of its own, and a card that read `AppModel` there
/// crashed the app on the hold. The row hands it the picture.
struct MessagePreviewCard: View {
    let message: Message
    /// The message's first picture, for a message of only images.
    let picture: CGImage?

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
            if preview.blocks.isEmpty, !message.images.isEmpty {
                ImageThumbnail(picture: picture, side: 200)
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
