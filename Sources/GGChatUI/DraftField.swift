import GGChatCore
import SwiftUI

/// The local composer's message field and what goes with it: the images the
/// draft carries, a way to add one, and Send or Stop. `Composer` draws the
/// glass around it.
///
/// An image comes from the photo picker, a paste or a drop, and every one
/// goes through `ImageDownscale` before it joins the draft. Draw is pressed
/// for one message, where the provider is gglib (`DrawToggle`). A draft refused
/// on its way out keeps its text and its images.
struct DraftField: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Draft()
    @State private var preparing = 0
    let conversation: Conversation

    private var streaming: Bool {
        model.isStreaming(conversation.id)
    }

    var body: some View {
        let canSee = model.canSee(conversation)
        VStack(alignment: .leading, spacing: 8) {
            if !draft.images.isEmpty || preparing > 0 {
                AttachmentStrip(images: draft.images, preparing: preparing > 0) { draft.remove($0) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                AddImageButtons(
                    disabled: streaming, refusal: canSee ? nil : "This model cannot read images.", take: take)
                // Only for gglib, which is the one server that draws.
                if model.offersDrawing(for: conversation) {
                    DrawToggle(
                        isOn: draft.draws, refusal: model.drawRefusal(for: conversation), disabled: streaming
                    ) {
                        draft.draws = $0
                    } say: {
                        model.lastError = $0
                    }
                }
                field
                sendButton
            }
        }
        .dropsImages(take)
    }

    private var field: some View {
        TextField("Message", text: $draft.text, axis: .vertical)
            .lineLimit(1...8)
            .textFieldStyle(.plain)
            .accessibilityIdentifier("composer")
            .padding(.vertical, 8)
            .padding(.leading, 6)
            .onSubmit(sendIfPossible)
            .disabled(streaming)
            .pastesImages(take)
    }

    private var sendButton: some View {
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

    /// False while any reply is in flight, even in another conversation, and
    /// while a hub is still writing this one's last reply: the model would
    /// refuse the send. A draft is text, images, or both; one with an image
    /// still being made ready waits for it.
    private var canSend: Bool {
        let provider = model.provider(for: conversation)
        return draft.hasContent && preparing == 0 && provider != nil
            && (conversation.model ?? provider?.defaultModel) != nil && model.takesTurn(conversation)
    }

    private func sendIfPossible() {
        guard canSend, !streaming else { return }
        draft.send(through: model)
    }

    // MARK: - Adding images

    private func take(_ files: [Data]) {
        Task { await add(files) }
    }

    /// Each image made ready off the main actor, in the order given. One the
    /// model cannot read is refused at once with gglib's sentence, and one
    /// that cannot be made ready says why; the same image twice is one.
    private func add(_ files: [Data]) async {
        guard !files.isEmpty else { return }
        guard model.admitsImages(to: conversation) else { return }
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
