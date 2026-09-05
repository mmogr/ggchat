import GGChatCore
import SwiftUI

/// The app's three custom glass elements, and only these, inside one
/// container so they sample the transcript beneath as one system: the
/// composer, the model pill, and the status pill.
struct Composer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var glass
    @State private var draft = ""
    @State private var pickingModel = false
    let conversation: Conversation

    private var provider: ProviderConfig? {
        model.provider(for: conversation)
    }

    private var streaming: Bool {
        model.isStreaming(conversation.id)
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                pills
                composer
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .task(id: provider?.id) {
            guard let provider else { return }
            if provider.isPipe, model.pipeSession(for: provider.id) == nil {
                await model.connectPipe(for: provider)
            }
            if model.models(for: provider.id).isEmpty {
                await model.refreshModels(for: provider)
            }
        }
        .sensoryFeedback(.success, trigger: model.connectedPulse)
    }

    /// Side by side when they fit, stacked at accessibility sizes.
    @ViewBuilder
    private var pills: some View {
        let status = model.pipeStatus(for: conversation)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                modelPill
                if let status { statusPill(status) }
            }
        } else {
            HStack(spacing: 8) {
                modelPill
                if let status { statusPill(status) }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Composer capsule

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...8)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.leading, 6)
                .onSubmit(sendIfPossible)
                .disabled(streaming)
            Button {
                if streaming { model.stop() } else { sendIfPossible() }
            } label: {
                Image(systemName: streaming ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!streaming && !canSend)
            .accessibilityLabel(streaming ? "Stop" : "Send")
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && provider != nil
            && (conversation.model ?? provider?.defaultModel) != nil
    }

    private func sendIfPossible() {
        guard canSend, !streaming else { return }
        let text = draft
        draft = ""
        model.send(text)
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

    /// Quiet while connected; when the other machine is gone it becomes the
    /// reconnect button.
    private func statusPill(_ status: PipeStatus) -> some View {
        Button {
            guard status == .closed, let provider else { return }
            Task { await model.reconnectPipe(for: provider) }
        } label: {
            Label(statusText(status), systemImage: statusSymbol(status))
                .font(.callout)
                .symbolEffect(.variableColor.iterative, isActive: status == .idle && !reduceMotion)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(status != .closed)
        .glassEffect(.regular.interactive(status == .closed), in: .capsule)
        .glassEffectID("status", in: glass)
        .glassEffectTransition(.matchedGeometry)
        .accessibilityLabel("Connection \(statusText(status))")
        .accessibilityHint(status == .closed ? "Reconnects" : "")
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
