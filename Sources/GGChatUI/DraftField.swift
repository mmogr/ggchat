import GGChatCore
import SwiftUI

/// The local composer's message field and what goes with it: the images the
/// draft carries, a way to add one, and Send or Stop. `Composer` draws the
/// glass around it.
///
/// An image comes from the photo picker, a paste or a drop, and every one
/// goes through `ImageDownscale` before it joins the draft. Draw is pressed
/// for one message, where the provider is gglib (`DrawToggle`), and the
/// image model is chosen on the line over the field (`DrawsWithLine`) where
/// its Mac lists some. A draft refused on its way out keeps its text and
/// its images.
struct DraftField: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Draft()
    @State private var preparing = 0
    #if os(iOS)
        /// Set for a conversation a quick action started on the camera.
        @State private var opensCamera = false
    #endif
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
            DrawsWithLine(
                isOn: draft.draws, refusal: model.drawRefusal(for: conversation),
                model: model.drawsWith(for: conversation), menu: model.drawMenu(for: conversation),
                choosing: model.drawAwaitsChoice(for: conversation), refused: model.drawChoiceRefused(for: conversation)
            ) {
                model.setImageModel($0, for: conversation.id)
            }
            ComposerRows {
                field
            } leading: {
                #if os(iOS)
                    AddImageButtons(
                        disabled: streaming, refusal: canSee ? nil : "This model cannot read images.", take: take,
                        opensCamera: $opensCamera)
                #else
                    AddImageButtons(
                        disabled: streaming, refusal: canSee ? nil : "This model cannot read images.", take: take)
                #endif
                // Only for gglib, which is the one server that draws.
                if model.offersDrawing(for: conversation) {
                    DrawToggle(
                        isOn: draft.draws, refusal: model.drawRefusal(for: conversation), disabled: streaming,
                        choosing: model.drawAwaitsChoice(for: conversation)
                    ) {
                        draft.draws = $0
                    } say: {
                        model.lastError = $0
                    }
                }
            } send: {
                sendButton
            }
        }
        .dropsImages(take)
        .onChange(of: model.composerStart, initial: true) { begin() }
    }

    /// Begins as the quick action that started this conversation asked:
    /// with Draw pressed, or on the camera.
    private func begin() {
        switch model.takeComposerStart(for: conversation.id) {
        case .draw:
            draft.draws = true
        case .camera:
            #if os(iOS)
                opensCamera = true
            #endif
        case .newChat, nil:
            break
        }
    }

    private var field: some View {
        TextField("Message", text: $draft.text, axis: .vertical)
            .lineLimit(1...8)
            .textFieldStyle(.plain)
            .accessibilityIdentifier("composer")
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
