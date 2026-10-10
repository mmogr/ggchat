import GGChatCore
import SwiftUI

/// Edits one message of a chat (ADR 0010). A question is asked again, by
/// Send, with the images it carries; a reply is kept as written, by Save.
/// An edit that would rewrite a saved reply opens a new branch, and the chat
/// it was made on is kept.
struct MessageEditor: View {
    @Environment(\.dismiss) private var dismiss
    let message: Message
    /// Makes the edit, the chat's own way.
    let save: (String) -> Void
    @State private var text: String

    init(message: Message, save: @escaping (String) -> Void) {
        self.message = message
        self.save = save
        _text = State(initialValue: message.content)
    }

    /// Whether `text` changes the message: not blank, unless the message
    /// carries images, and not the same but for the space around it.
    static func canSave(_ text: String, for message: Message) -> Bool {
        message.edited(to: text).map { $0 != message.content } ?? false
    }

    private var isQuestion: Bool {
        message.role == .user
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(.horizontal)
                .accessibilityLabel(isQuestion ? "Question" : "Reply")
                .navigationTitle(isQuestion ? "Edit question" : "Edit reply")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isQuestion ? "Send" : "Save") {
                            save(text)
                            dismiss()
                        }
                        .disabled(!Self.canSave(text, for: message))
                    }
                }
        }
    }
}
