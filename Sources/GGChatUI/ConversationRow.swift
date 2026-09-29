import GGChatCore
import SwiftUI

/// One conversation in the list: its title, what it talks to, and, beside
/// the title, whether a reply is still being written or waits unread.
struct ConversationRow: View {
    @Environment(AppModel.self) private var model
    let conversation: Conversation

    var body: some View {
        let mark = model.mark(for: conversation)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .fontWeight(mark == .unread ? .semibold : nil)
                    .lineLimit(1)
                if let mark {
                    Spacer(minLength: 4)
                    ConversationMarkView(mark: mark)
                }
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !conversation.title.isEmpty { return conversation.title }
        let derived = conversation.derivedTitle
        return derived.isEmpty ? "New conversation" : derived
    }

    private var subtitle: String {
        let provider = model.provider(for: conversation)?.name ?? "No provider"
        if let modelName = conversation.model { return "\(provider) · \(modelName)" }
        return provider
    }
}

/// The mark itself: a small symbol and a word, in the caption size of the
/// line under the title. Unread takes the tint, writing stays secondary, and
/// the word says which either way.
struct ConversationMarkView: View {
    let mark: ConversationMark

    var body: some View {
        Label(mark.word, systemImage: mark.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .imageScale(.small)
            .foregroundStyle(mark == .unread ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .fixedSize()
            .accessibilityLabel(mark.accessibilityLabel)
    }
}
