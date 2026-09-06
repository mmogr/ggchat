import GGChatCore
import SwiftUI

/// One stored turn. Flat: a role label, reasoning collapsed, then the
/// content as markdown blocks. A partial reply shows the error under it and
/// a Continue button.
struct MessageRow: View {
    @Environment(AppModel.self) private var model
    let message: Message
    let isLast: Bool
    let error: ProviderError?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoleLabel(role: message.role)
            if let reasoning = message.reasoning, !reasoning.isEmpty {
                ReasoningRow(text: reasoning, isThinking: false)
            }
            MarkdownBlocksView(blocks: MarkdownBlocks.parse(message.content))
            if message.isPartial, isLast {
                partialFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partialFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error {
                Text(error.errorDescription ?? "The reply stopped early.")
                    .font(.callout)
                    .foregroundStyle(.red)
                if let hint = error.whereToLook.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Stopped before the reply finished.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Continue", systemImage: "arrow.turn.down.right") {
                model.continueReply()
            }
            .buttonStyle(.bordered)
            .disabled(model.isStreaming)
        }
        .padding(.top, 2)
    }
}

struct RoleLabel: View {
    let role: Role

    var body: some View {
        Text(role == .user ? "You" : role == .assistant ? "Assistant" : "System")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Collapsed by default. While the model is still thinking the label says
/// so, with a subtle symbol effect instead of a spinner.
struct ReasoningRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let isThinking: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            Label(isThinking ? "Thinking" : "Reasoning", systemImage: "brain")
                .font(.callout)
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: isThinking && !reduceMotion)
                .accessibilityLabel(
                    isThinking ? "Thinking, in progress" : "Reasoning, \(expanded ? "expanded" : "collapsed")")
        }
    }
}
