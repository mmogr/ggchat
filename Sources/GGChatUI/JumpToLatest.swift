import SwiftUI

/// When a transcript offers its way back to the latest message: once its
/// bottom is more than half a screen out of sight. A chat shorter than its
/// screen never does, and nor does one scrolled up only a little.
enum JumpToLatest {
    /// How much of the visible height has to be scrolled past first.
    nonisolated static let threshold: CGFloat = 0.5

    /// How far the content's bottom is below what can be read of it: zero
    /// at the bottom, and below zero for content shorter than its screen.
    /// The visible rect is the scroll view's whole frame in the content's
    /// space, so the composer's inset at its foot covers its last stretch.
    nonisolated static func distanceFromBottom(
        contentHeight: CGFloat, visibleMaxY: CGFloat, bottomInset: CGFloat
    ) -> CGFloat {
        contentHeight - (visibleMaxY - bottomInset)
    }

    nonisolated static func shows(distanceFromBottom distance: CGFloat, viewport: CGFloat) -> Bool {
        viewport > 0 && distance > viewport * threshold
    }

    /// Whether a chat at its latest is taken back there after its foot is
    /// covered more, as when the keyboard comes up as a reply ends: the
    /// scroll view keeps its offset, and the latest reply would sit under the
    /// keyboard. At its latest is wherever the button would not show: a
    /// finished reply's row is drawn again a few points taller or shorter,
    /// and a keyboard back before the chat settled found it short of its very
    /// bottom and left it there. A chat scrolled well up stays where it is.
    nonisolated static func keepsToLatest(
        distanceBefore: CGFloat, viewportBefore: CGFloat, insetBefore: CGFloat, insetAfter: CGFloat
    ) -> Bool {
        !shows(distanceFromBottom: distanceBefore, viewport: viewportBefore) && insetAfter > insetBefore
    }

    /// The id of the transcript's foot, which the button scrolls to.
    nonisolated static let foot = "jump-to-latest-foot"
}

extension View {
    /// A transcript's way back to its latest message, a round button over its
    /// foot that shows once it is scrolled well up, with a dot while a reply
    /// is `replying` out of sight; and a drag down on it that takes the
    /// keyboard with it. Applied to the `ScrollView` itself, inside the
    /// composer's inset, so the button sits above the composer. A new `chat`
    /// shown in the same view opens at its latest, wherever the last was left.
    func jumpsToLatest(replying: Bool, in chat: some Hashable) -> some View {
        modifier(JumpsToLatest(replying: replying, chat: chat))
    }

    /// Marks the foot of a transcript's content, where `jumpsToLatest` goes.
    func footOfTheLatest() -> some View {
        background(alignment: .bottom) {
            Color.clear.frame(height: 0).id(JumpToLatest.foot)
        }
    }
}

/// The way back scrolls to the foot through a reader rather than binding the
/// scroll position: a bound position takes over from the transcript's bottom
/// anchor, and the transcript then stayed where it was when the keyboard came
/// back up after a reply, instead of keeping to its latest.

private struct JumpsToLatest<Chat: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let replying: Bool
    let chat: Chat
    @State private var shown = false

    /// What the scroll geometry says of the foot, in points.
    private struct Reading: Equatable {
        var distance: CGFloat
        var viewport: CGFloat
        var inset: CGFloat
    }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            transcript(content, proxy: proxy)
        }
    }

    private func transcript(_ content: Content, proxy: ScrollViewProxy) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Reading.self) { geometry in
                let visible = geometry.visibleRect
                let insets = geometry.contentInsets
                return Reading(
                    distance: JumpToLatest.distanceFromBottom(
                        contentHeight: geometry.contentSize.height, visibleMaxY: visible.maxY,
                        bottomInset: insets.bottom),
                    viewport: visible.height - insets.top - insets.bottom, inset: insets.bottom)
            } action: { before, after in
                shown = JumpToLatest.shows(distanceFromBottom: after.distance, viewport: after.viewport)
                if JumpToLatest.keepsToLatest(
                    distanceBefore: before.distance, viewportBefore: before.viewport, insetBefore: before.inset,
                    insetAfter: after.inset)
                {
                    proxy.scrollTo(JumpToLatest.foot, anchor: .bottom)
                }
            }
            .onChange(of: chat) { proxy.scrollTo(JumpToLatest.foot, anchor: .bottom) }
            .overlay(alignment: .bottom) {
                // The fade is the overlay's alone, so nothing in the
                // transcript is animated along with it.
                ZStack {
                    if shown {
                        button(proxy)
                            .padding(.bottom, 8)
                            .keptOffTheFold(maxWidth: 760)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: shown)
            }
    }

    /// The system's glass, not a fourth custom surface. Whether a reply is
    /// on its way is in the label, which VoiceOver reads; the dot is not read.
    private func button(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(JumpToLatest.foot, anchor: .bottom) }
        } label: {
            Label(replying ? "Jump to the latest, a reply is coming" : "Jump to the latest", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .overlay(alignment: .topTrailing) {
            if replying {
                Circle()
                    .fill(.tint)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("jump-to-latest")
    }
}
