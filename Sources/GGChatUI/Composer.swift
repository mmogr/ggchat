import GGChatCore
import SwiftUI

/// The app's three custom glass elements, and only these, inside one
/// container so they sample the transcript beneath as one system: the
/// composer, the model pill, and the status pill.
struct Composer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Namespace private var glass
    @State private var pickingModel = false
    let conversation: Conversation

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
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
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
    /// edge, so the ring and the status pill stay where they are while the
    /// model pill grows upward into its list.
    @ViewBuilder
    private var pills: some View {
        let status = model.pipeStatus(for: conversation)
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
                if let status { statusPill(status) }
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
    /// with one id, so the pill grows into the list.
    private var modelPill: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .accessibilityHint("Opens the model list")
            if pickingModel {
                Divider()
                modelList
            }
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: pickingModel ? 18 : 20))
        .glassEffectID("model", in: glass)
    }

    private var modelList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let provider {
                    let models = model.models(for: provider.id)
                    if models.isEmpty {
                        Text("No models listed yet.")
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                    ForEach(models) { info in
                        Button {
                            model.select(model: info.id, for: conversation.id)
                            withAnimation(reduceMotion ? nil : .snappy) { pickingModel = false }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(info.id)
                                    if let detail = info.description {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if info.id == currentModelID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Pick a provider for this conversation first.")
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private var currentModelID: String? {
        conversation.model ?? provider?.defaultModel
    }

    private var modelLabel: String {
        currentModelID ?? "Choose a model"
    }

    // MARK: - Status pill

    /// Quiet while connected, and a way back at every moment the app is not
    /// already dialling — including over a pill that reads "Direct", which
    /// is the state a status goes stale in. `AppModel.canReconnect(_:)`
    /// carries the reasoning.
    private func statusPill(_ status: PipeStatus) -> some View {
        let offered = provider.map { model.canReconnect($0.id) } ?? false
        return Button {
            guard offered, let provider else { return }
            Task { await model.reconnectPipe(for: provider) }
        } label: {
            Label(statusText(status), systemImage: statusSymbol(status))
                .font(.callout)
                .symbolEffect(.variableColor.iterative, isActive: status == .idle && !reduceMotion)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        // Only the closed pill is tinted: it is the one asking to be pressed.
        // The others read as status and are pressable without saying so.
        .foregroundStyle(status == .closed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .disabled(!offered)
        .glassEffect(.regular.interactive(offered), in: .capsule)
        .glassEffectID("status", in: glass)
        .glassEffectTransition(.matchedGeometry)
        .accessibilityLabel("Connection \(statusText(status))")
        .accessibilityHint(offered ? "Reconnects" : "")
    }

    private func statusText(_ status: PipeStatus) -> String {
        switch status {
        case .idle: "Connecting"
        case .direct: "Direct"
        case .relayed: "Relayed"
        case .closed: "Reconnect"
        }
    }

    private func statusSymbol(_ status: PipeStatus) -> String {
        switch status {
        case .idle, .direct, .relayed: "antenna.radiowaves.left.and.right"
        case .closed: "antenna.radiowaves.left.and.right.slash"
        }
    }
}
