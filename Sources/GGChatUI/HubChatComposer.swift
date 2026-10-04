import GGChatCore
import SwiftUI

/// The reply a Mac is writing to its chat open, under the chat's rows: the
/// question this phone sent, with its images, until the rows read from the
/// Mac hold it, then the reply as it arrives, a line for each tool it calls.
struct HubLiveReplyRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let reply: HubLiveReply
    let rows: OpenHubChat.State

    /// Whether the rows on screen already end with the question.
    private var rowsHoldTheQuestion: Bool {
        guard case .read(let messages) = rows, let last = messages.last else { return false }
        return last.role == .user && last.content == reply.question
            && last.images.map(\.id) == reply.images.map(\.id)
    }

    var body: some View {
        if let question = reply.question, !rowsHoldTheQuestion {
            MessageRow(
                message: Message(
                    role: .user, content: question, createdAt: .distantPast, images: reply.images.map(\.ref)),
                showsEnding: false, advice: nil, writingLine: nil, imagesFromHub: true)
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

/// Where a Mac's chat is carried on: a message field with the images its
/// draft carries, whose button is Stop while the Mac writes the reply, and
/// the sentence the last send left. An image is picked, pasted or dropped
/// as in the local composer, through the one downscale, and a draft may be
/// images alone. Stock controls: the app's glass is the local composer's
/// alone.
struct HubComposer: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Draft()
    @State private var preparing = 0
    let notice: String?
    /// The text and images of a send that went nowhere, put back.
    let unsent: Draft?

    private var canSend: Bool {
        draft.hasContent && preparing == 0 && !model.openHubChatIsWriting
    }

    var body: some View {
        let writing = model.openHubChatIsWriting
        let canSee = model.openedHubChat.map(model.canSeeHubChat) ?? true
        VStack(alignment: .leading, spacing: 8) {
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !draft.images.isEmpty || preparing > 0 {
                AttachmentStrip(images: draft.images, preparing: preparing > 0) { draft.remove($0) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                AddImageButtons(
                    disabled: writing, refusal: canSee ? nil : "This model cannot read images.", take: take)
                TextField("Message", text: $draft.text, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("hub-composer")
                    .onSubmit(sendIfPossible)
                    .disabled(writing)
                    .pastesImages(take)
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
        .dropsImages(take)
        .onChange(of: unsent, initial: true) { _, back in
            guard back != nil, draft == Draft(), let back = model.takeUnsentHubDraft() else { return }
            draft = back
        }
    }

    private func sendIfPossible() {
        guard canSend else { return }
        let sent = draft
        draft = Draft()
        model.sendToHubChat(sent.text, images: sent.images)
    }

    private func take(_ files: [Data]) {
        Task { await add(files) }
    }

    /// Each image made ready off the main actor, in the order given. One the
    /// chat's model cannot read is refused at once with gglib's sentence,
    /// and one that cannot be made ready says why.
    private func add(_ files: [Data]) async {
        guard !files.isEmpty, model.admitsImagesToHubChat() else { return }
        preparing += files.count
        defer { preparing -= files.count }
        for made in await ImageIntake.prepare(files) {
            switch made {
            case .success(let image):
                draft.add(image)
            case .failure(let refusal):
                model.lastError = refusal.errorDescription
            }
        }
    }
}
