import GGChatCore
import SwiftUI

/// Edits what the model is told ahead of every message in one conversation.
/// A sheet from the conversation's toolbar, never a row in its transcript.
///
/// The field starts from the prompt as it was when the sheet opened, and
/// Save hands the text to `AppModel.setSystemPrompt(_:for:)` by id rather
/// than saving a copy of the conversation: a reply can finish while the
/// sheet is up, and a copy taken before it would write over it.
struct SystemPromptView: View {
    let conversation: Conversation

    var body: some View {
        NavigationStack {
            SystemPromptForm(conversation: conversation)
        }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}

/// The field, Cancel and Save, for the sheet's stack or pushed on another:
/// on an open iPhone Duo on its side, on the chat's panel beside it. Either
/// way out is the stack's, a sheet dismissed or a page popped.
struct SystemPromptForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let conversationID: UUID

    init(conversation: Conversation) {
        _text = State(initialValue: conversation.systemPrompt ?? "")
        conversationID = conversation.id
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("system-prompt")
            } footer: {
                Text(
                    "Sent ahead of every message in this conversation. "
                        + "Changes apply from the next message; leave it empty to send none."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System prompt")
        #if os(iOS)
            // Pushed, Cancel is the way back, as in the sheet.
            .navigationBarBackButtonHidden()
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.setSystemPrompt(text, for: conversationID)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    SystemPromptView(conversation: AppModel.preview.conversations[0])
        .environment(AppModel.preview)
}
