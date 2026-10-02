import GGChatCore
import SwiftUI

/// The reply a Mac is writing to its chat open, under the chat's rows: the
/// question this phone sent, until the rows read from the Mac hold it, then
/// the reply as it arrives, a line for each tool it calls.
struct HubLiveReplyRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let reply: HubLiveReply
    let rows: OpenHubChat.State

    /// Whether the rows on screen already end with the question.
    private var rowsHoldTheQuestion: Bool {
        guard case .read(let messages) = rows, let last = messages.last else { return false }
        return last.role == .user && last.content == reply.question
    }

    var body: some View {
        if let question = reply.question, !rowsHoldTheQuestion {
            MessageRow(
                message: Message(role: .user, content: question, createdAt: .distantPast), showsEnding: false,
                advice: nil, writingLine: nil)
        }
        VStack(alignment: .leading, spacing: 6) {
            RoleLabel(role: .assistant)
            if !reply.reasoning.isEmpty {
                ReasoningRow(text: reply.reasoning, isThinking: reply.content.isEmpty && !reply.ended)
            }
            ForEach(Array(reply.tools.enumerated()), id: \.offset) { _, line in
                Label(line, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if reply.content.isEmpty, !reply.ended {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for the first token")
            } else {
                MarkdownBlocksView(blocks: reply.blocks)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: reply.content.count)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Where a Mac's chat is carried on: a message field whose button is Stop
/// while the Mac writes the reply, and the sentence the last send left.
/// Stock controls: the app's glass is the local composer's alone.
struct HubComposer: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    let notice: String?
    /// The text of a send that went nowhere, put back into the field.
    let unsent: String?

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.openHubChatIsWriting
    }

    var body: some View {
        let writing = model.openHubChatIsWriting
        VStack(alignment: .leading, spacing: 8) {
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("hub-composer")
                    .onSubmit(sendIfPossible)
                    .disabled(writing)
                Button {
                    if writing { model.stopHubReply() } else { sendIfPossible() }
                } label: {
                    Image(systemName: writing ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!writing && !canSend)
                .accessibilityLabel(writing ? "Stop" : "Send")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .onChange(of: unsent, initial: true) { _, text in
            guard text != nil, draft.isEmpty, let back = model.takeUnsentHubText() else { return }
            draft = back
        }
    }

    private func sendIfPossible() {
        guard canSend else { return }
        let text = draft
        draft = ""
        model.sendToHubChat(text)
    }
}
