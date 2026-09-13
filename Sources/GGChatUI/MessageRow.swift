import GGChatCore
import SwiftUI

/// One stored turn. Flat: a role label, reasoning collapsed, then the
/// content as markdown blocks. The last one, once nothing is streaming after
/// it, says how its turn ended: under a partial reply, with Continue, and
/// under a question with no reply, with Retry and the reason when something
/// gave one.
struct MessageRow: View {
    @Environment(AppModel.self) private var model
    let message: Message
    /// Whether this row says how its turn ended: it is the last one, and no
    /// reply is streaming into the conversation after it.
    let showsEnding: Bool
    /// What the provider behind this conversation adds about the failure,
    /// when it has something to add.
    let advice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoleLabel(role: message.role)
            if let reasoning = message.reasoning, !reasoning.isEmpty {
                ReasoningRow(text: reasoning, isThinking: false)
            }
            MarkdownBlocksView(blocks: MarkdownBlocks.parse(message.content))
            if showsEnding {
                if message.isPartial {
                    partialFooter
                } else if message.role == .user {
                    unansweredFooter
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partialFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure = message.failure {
                FailureLines(failure: failure, advice: advice)
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

    /// Under a question with no reply at all: why, when something said so,
    /// and a way to ask it again. Only under the last one, like Continue, so
    /// a question asked again in other words does not keep its refusal on
    /// screen.
    private var unansweredFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure = message.failure {
                FailureLines(failure: failure, advice: advice)
            }
            Button("Retry", systemImage: "arrow.clockwise") {
                model.retry()
            }
            .buttonStyle(.bordered)
            .disabled(model.isStreaming)
        }
        .padding(.top, 2)
    }
}

/// The sentence that says why, verbatim, then the line about where to look
/// and whatever the provider adds. The symbol is what keeps the sentence from
/// reading as part of the question it sits under.
struct FailureLines: View {
    let failure: Failure
    let advice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
            if let hint = failure.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let advice {
                Text(advice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
