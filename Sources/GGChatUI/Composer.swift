import GGChatCore
import SwiftUI

/// The app's three custom glass elements, and only these, inside one
/// container so they sample the transcript beneath as one system: the
/// composer, the model pill, and the status pill, which says how a pipe is
/// or how this device's engine is with the conversation's model.
struct Composer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Namespace private var glass
    @State private var pickingModel = false
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let conversation: Conversation
    /// The chat's height free of its top bar and the keyboard, which the
    /// model list is sized from; 0 until it has been measured.
    var room: CGFloat = 0

    private var provider: ProviderConfig? {
        model.provider(for: conversation)
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                pills
                // A plain line, not a fourth glass element, and what VoiceOver
                // reads is what is shown.
                if let caption = model.silenceCaption(for: conversation, locale: locale, calendar: calendar) {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                composer
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .keptOffTheFold(maxWidth: 760)
        .task(id: provider?.id) {
            // Handed to the model and not awaited: SwiftUI can cancel this
            // task as soon as it starts, and the work must outlive that. See
            // `AppModel+Opening`.
            if let provider { model.open(provider) }
        }
        .sensoryFeedback(.success, trigger: model.connectedPulse)
    }

    /// Side by side when they fit, stacked at accessibility sizes, with the
    /// context ring at the trailing end once a reply has left a reading. The
    /// ring is plain drawing, not glass. The row is aligned on its bottom
    /// edge, so the ring stays where it is while the model pill grows upward
    /// into its list. On a phone the open list takes the status pill's room
    /// on that row, so it is wide enough to read; its sections say how each
    /// provider is. A wider window keeps the pill.
    @ViewBuilder
    private var pills: some View {
        let status = model.sessionStatus(for: conversation)
        let reading = model.contextReading(for: conversation)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                modelPill
                if let status { statusPill(status) }
                if let reading { ContextRing(reading: reading) }
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                modelPill
                if let status, !listTakesTheRow { statusPill(status) }
                Spacer(minLength: 0)
                if let reading { ContextRing(reading: reading) }
            }
        }
    }

    // MARK: - Composer capsule

    /// The field, its images and Send, in `DraftField`; the glass is drawn
    /// here, with the other two.
    private var composer: some View {
        DraftField(conversation: conversation)
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Model pill

    /// One glass surface that is a pill when closed and a list when open,
    /// with one id, so the pill grows into the list. The list opens above
    /// the pill, which stays where it was and goes on naming the model, so
    /// nothing in the list says it again.
    private var modelPill: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pickingModel {
                ModelListPanel(conversation: conversation, room: room) {
                    withAnimation(reduceMotion ? nil : .snappy) { pickingModel = false }
                }
                Divider()
            }
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { pickingModel.toggle() }
            } label: {
                Label(modelLabel, systemImage: "cpu")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Model, \(modelLabel)")
            .accessibilityHint(pickingModel ? "Closes the model list" : "Opens the model list")
        }
        // The open list is as wide as the row allows, to a width that reads
        // as a list and not a page on an iPad or a Mac.
        .frame(maxWidth: pickingModel ? 440 : nil, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: pickingModel ? 18 : 20))
        .glassEffectID("model", in: glass)
    }

    /// Whether the open list has the pills' row to itself: only in a
    /// compact width, where beside the status pill it would be too narrow
    /// to read.
    private var listTakesTheRow: Bool {
        #if os(iOS)
            pickingModel && sizeClass == .compact
        #else
            false
        #endif
    }

    private var currentModelID: String? {
        conversation.model ?? provider?.defaultModel
    }

    private var modelLabel: String {
        currentModelID ?? "Choose a model"
    }

    // MARK: - Status pill

    /// A pipe's is quiet while connected, and a way back at every moment the
    /// app is not already dialling — including over a pill that reads
    /// "Direct", which is the state a status goes stale in;
    /// `AppModel.canReconnect(_:)` carries the reasoning. The engine's says
    /// how the conversation's model is, loads it again once it could not be
    /// loaded, and opens the model browser once it was refused as too big
    /// (`AppModel.press(_:in:)`).
    private func statusPill(_ status: SessionStatus) -> some View {
        let offered = model.offersPress(on: status, in: conversation)
        return Button {
            guard offered else { return }
            model.press(status, in: conversation)
        } label: {
            Label(status.words, systemImage: status.symbol)
                .font(.callout)
                .monospacedDigit()
                .symbolEffect(.variableColor.iterative, isActive: status.isUnderWay && !reduceMotion)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(status.asksToBePressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .disabled(!offered)
        .glassEffect(.regular.interactive(offered), in: .capsule)
        .glassEffectID("status", in: glass)
        .glassEffectTransition(.matchedGeometry)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityHint(offered ? status.accessibilityHint : "")
    }
}
