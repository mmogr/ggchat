import GGChatCore
import SwiftUI

/// The transcript. Flat text on the scrolling background; the composer and
/// the pills arrive with streaming.
struct ChatView: View {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(conversation.messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == .user ? "You" : "Assistant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .overlay {
            if conversation.messages.isEmpty {
                ContentUnavailableView("Empty conversation", systemImage: "text.bubble")
            }
        }
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var title: String {
        if !conversation.title.isEmpty { return conversation.title }
        let derived = conversation.derivedTitle
        return derived.isEmpty ? "New conversation" : derived
    }
}
