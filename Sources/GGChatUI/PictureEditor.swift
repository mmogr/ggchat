import CoreGraphics
import GGChatCore
import SwiftUI

/// A picture the drawing tool made, fixed or drawn again. Fix: brush over
/// the part that is wrong, and only that part is drawn again. Redo: the
/// whole picture is drawn again from itself, as far from it as the slider
/// says. While the Mac draws, the stage is said in words, the latest look
/// lies over the picture, and Stop ends it. The result is shown with the
/// choice to keep it, which adds it to the chat after the picture it came
/// from, to try again, or to discard it. Nothing is kept until Keep.
///
/// While a render, a result or a Keep is in hand there is no way back but
/// Stop, Discard and Keep, so a picture that took minutes is not lost to a
/// swipe. What is chosen and what is drawn is `PictureEditing`'s.
///
/// On iOS 27.1 the picture and the controls are arranged around the screen
/// and its fold (`arranged`); everywhere else they are one scrolling column
/// (`stacked`), which is what the editor had before.
struct PictureEditor: View {
    @Environment(\.locale) private var locale
    @Bindable var editing: PictureEditing
    /// The picture as the chat shows it.
    let original: CGImage?
    /// Closes the sheet once the chat holds the newer picture.
    let close: () -> Void
    #if os(iOS) && compiler(>=6.4)
        /// Whether the editor lies across an active fold.
        @State private var folded = false
    #endif

    var body: some View {
        layout
            .navigationTitle(editing.drawn == nil ? "Fix or redo this picture" : "Keep this picture?")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationBarBackButtonHidden(editing.holdsWork)
            .interactiveDismissDisabled(editing.holdsWork)
            .onChange(of: editing.isKept) { _, kept in
                if kept { close() }
            }
            .onDisappear { editing.leave() }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS) && compiler(>=6.4)
            if #available(iOS 27.1, *) {
                arranged
            } else {
                stacked
            }
        #else
            stacked
        #endif
    }

    /// One column: what to do, the picture, then the controls.
    private var stacked: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if editing.isEditing { modes }
                canvas(maxHeight: 440)
                controls
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    /// The picture, with the brush while a part is being chosen.
    private func canvas(maxHeight: CGFloat) -> some View {
        PictureCanvas(
            picture: shown, look: look, natural: editing.size,
            strokes: editing.isEditing && editing.mode == .fix ? editing.strokes : [],
            brushes: editing.isEditing && editing.mode == .fix, begin: editing.begin, extend: editing.extend
        )
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .accessibilityElement()
        .accessibilityLabel(
            Self.label(drawn: editing.drawn != nil, comparing: editing.comparing, mode: editing.mode)
        )
        // VoiceOver passes touches straight through here, so the
        // part to fix can be brushed with it on.
        .accessibilityAddTraits(editing.isEditing && editing.mode == .fix ? .allowsDirectInteraction : [])
    }

    /// What follows the picture: why something failed, the choices, the
    /// actions.
    @ViewBuilder
    private var controls: some View {
        if let why = Self.failure(of: editing) {
            Label(why, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        }
        if editing.isEditing { PictureChoices(editing: editing) }
        actions
    }

    /// The picture under everything: the one drawn again, or the original
    /// while there is none or while the original is held up beside it.
    private var shown: CGImage? {
        guard !editing.comparing, let drawn = editing.drawnPicture else { return original }
        return drawn
    }

    private var look: CGImage? {
        guard case .drawing(let progress?) = editing.phase, let frame = progress.frame else { return nil }
        return ImageDownscale.thumbnail(of: frame, longEdge: 512)
    }

    private var modes: some View {
        ViewThatFits {
            HStack(spacing: 8) { modeButtons }
            VStack(alignment: .leading, spacing: 8) { modeButtons }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What to do")
    }

    @ViewBuilder
    private var modeButtons: some View {
        PictureChoice(title: "Fix a part", isOn: editing.mode == .fix) { editing.choose(.fix) }
        PictureChoice(title: "Redo the whole picture", isOn: editing.mode == .redo) { editing.choose(.redo) }
    }

    @ViewBuilder
    private var actions: some View {
        switch editing.phase {
        case .idle, .failed:
            VStack(alignment: .leading, spacing: 8) {
                // Why the button is dimmed is said beside it, not only heard.
                if let why = editing.blocked {
                    Text(why)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(editing.askTitle) { editing.ask() }
                    .buttonStyle(.borderedProminent)
                    .disabled(editing.blocked != nil)
                    .accessibilityHint(editing.blocked ?? "")
            }
        case .drawing(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text(RedrawProgress.line(for: progress, in: locale))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Stop", systemImage: "stop.circle") { editing.stop() }
                    .buttonStyle(.bordered)
            }
        case .drawn, .keeping:
            VStack(alignment: .leading, spacing: 12) {
                HoldToCompare(comparing: $editing.comparing)
                ViewThatFits {
                    HStack(spacing: 8) { verdicts(editing.isKeeping) }
                    VStack(alignment: .leading, spacing: 8) { verdicts(editing.isKeeping) }
                }
            }
        }
    }

    @ViewBuilder
    private func verdicts(_ keeping: Bool) -> some View {
        Button(keeping ? "Keeping\u{2026}" : "Keep") { editing.keep() }
            .buttonStyle(.borderedProminent)
            .disabled(keeping)
        Button("Try again") { editing.ask() }
            .buttonStyle(.bordered)
            .disabled(keeping)
        Button("Discard", role: .destructive) { editing.discard() }
            .buttonStyle(.bordered)
            .disabled(keeping)
    }

    /// What is said under the picture when something went wrong: why the
    /// render failed, or why a drawn picture could not be kept.
    static func failure(of editing: PictureEditing) -> String? {
        if case .failed(let why) = editing.phase { return why }
        return editing.keepFailure
    }

    /// What VoiceOver calls the picture area.
    static func label(drawn: Bool, comparing: Bool, mode: PictureEditing.Mode) -> String {
        if drawn { return comparing ? "The picture" : "The picture drawn again" }
        return mode == .fix ? "The picture. Brush over the part to fix" : "The picture"
    }
}

#if os(iOS) && compiler(>=6.4)
    extension PictureEditor {
        /// The picture in one half and the controls in the other: side by
        /// side while the editor is wider than tall, the picture above the
        /// controls while it is taller, and on a half-open phone each on its
        /// own side of the fold, where the system sets the split. The
        /// controls scroll within their half, so a phone held upright loses
        /// none of them under the keyboard. Only Swift 6.4 has the iOS 27.1
        /// SDK these come from, so the layout before it is kept for CI.
        @available(iOS 27.1, *)
        fileprivate var arranged: some View {
            ArrangementView {
                canvas(maxHeight: .infinity)
                    .padding()
                    .layoutPriority(1)
                    .splitArrangementLayoutRatio(folded ? nil : 0.6)
            } secondary: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if editing.isEditing { modes }
                        controls
                    }
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .splitArrangementLayoutSize(minWidth: 300, minHeight: 220)
            }
            .arrangementViewStyle(.split)
            .onGeometryChange(for: Bool.self) {
                !Fold.divisions(in: $0).isEmpty
            } action: {
                folded = $0
            }
        }
    }
#endif

/// One of the two things to do, as a button that says whether it is chosen
/// by its fill and to VoiceOver.
private struct PictureChoice: View {
    let title: String
    let isOn: Bool
    let choose: () -> Void

    var body: some View {
        Group {
            if isOn {
                Button(title, action: choose).buttonStyle(.borderedProminent)
            } else {
                Button(title, action: choose).buttonStyle(.bordered)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Shows the original for as long as it is held. VoiceOver, which cannot
/// hold, turns it over with a press and hears which picture is shown.
private struct HoldToCompare: View {
    @Binding var comparing: Bool

    var body: some View {
        Label("Hold to see the original", systemImage: "eye")
            .font(.callout)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.quaternary, in: .capsule)
            .contentShape(.capsule)
            .onLongPressGesture(
                minimumDuration: 600, maximumDistance: 80, perform: {}, onPressingChanged: { comparing = $0 }
            )
            .accessibilityElement()
            .accessibilityLabel("Show the original")
            .accessibilityValue(comparing ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { comparing.toggle() }
    }
}
