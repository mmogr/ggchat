import CoreTransferable
import GGChatCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The local composer's message field and what goes with it: the images the
/// draft carries, a way to add one, and Send or Stop. `Composer` draws the
/// glass around it.
///
/// An image comes from the photo picker, a paste or a drop, and every one
/// goes through `ImageDownscale` before it joins the draft. A draft refused
/// on its way out keeps its text and its images.
struct DraftField: View {
    @Environment(AppModel.self) private var model
    @State private var draft = Draft()
    @State private var picked: [PhotosPickerItem] = []
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
                PhotosPicker(selection: $picked, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.body)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(streaming || !canSee)
                .help(canSee ? "Add an image" : "This model cannot read images.")
                .accessibilityLabel("Add an image")
                .accessibilityHint(canSee ? "" : "This model cannot read images.")
                .accessibilityIdentifier("add-image")
                #if os(iOS)
                    // iOS 26 has no paste destination for a view, and a text
                    // field pastes text alone, so an image is pasted here.
                    PasteButton(payloadType: ImageFile.self) { files in take(files) }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .disabled(streaming || !canSee)
                        .accessibilityIdentifier("paste-image")
                #endif
                field
                sendButton
            }
        }
        .dropDestination(for: ImageFile.self) { files, _ in
            take(files)
            return !files.isEmpty
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await take(items) }
        }
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
            #if os(macOS)
                .onPasteCommand(of: ImageFile.pasted) { providers in
                    Task { await take(providers) }
                }
            #endif
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

    private func take(_ files: [ImageFile]) {
        Task { await add(files.map(\.data)) }
    }

    private func take(_ items: [PhotosPickerItem]) async {
        var files: [Data] = []
        for item in items {
            if let file = try? await item.loadTransferable(type: ImageFile.self) { files.append(file.data) }
        }
        await add(files)
    }

    #if os(macOS)
        private func take(_ providers: [NSItemProvider]) async {
            var files: [Data] = []
            for provider in providers {
                if let data = await ImageFile.data(from: provider) { files.append(data) }
            }
            await add(files)
        }
    #endif

    /// Each image made ready off the main actor, in the order given. One the
    /// model cannot read is refused at once with gglib's sentence, and one
    /// that cannot be made ready says why; the same image twice is one.
    private func add(_ files: [Data]) async {
        guard !files.isEmpty else { return }
        guard model.admitsImages(to: conversation) else { return }
        preparing += files.count
        defer { preparing -= files.count }
        for data in files {
            let made = await Task.detached(priority: .userInitiated) {
                Result { () throws(ImageRefusal) in try ImageDownscale().prepare(data) }
            }.value
            switch made {
            case .success(let image):
                draft.add(image)
            case .failure(let refusal):
                model.lastError = refusal.errorDescription
            }
        }
    }
}

/// Any image, as the bytes it arrives in, from a paste, a drop or the photo
/// picker. `ImageDownscale` reads whichever kind it is.
nonisolated struct ImageFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { ImageFile(data: $0) }
    }

    #if os(macOS)
        /// What a paste is read for.
        static let pasted: [UTType] = [.image]

        /// The first image the provider holds, as bytes.
        @MainActor static func data(from provider: NSItemProvider) async -> Data? {
            guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) else {
                return nil
            }
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
            }
        }
    #endif
}
