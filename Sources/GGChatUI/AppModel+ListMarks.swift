import Foundation
import GGChatCore

/// What a conversation's row in the list says about its reply, beside its
/// title: a small mark and a word, never colour alone.
public enum ConversationMark: Equatable, Sendable {
    /// A reply is still being written: streaming in front, or a run the hub
    /// is writing away from this device.
    case writing
    /// A reply ended, finished, failed or given up, while another
    /// conversation was the one open, and this one has not been opened since.
    case unread

    /// The word shown beside the title.
    public var word: String {
        switch self {
        case .writing: "Writing"
        case .unread: "New"
        }
    }

    /// What VoiceOver reads for the mark, as part of the row.
    public var accessibilityLabel: String {
        switch self {
        case .writing: "Reply still being written"
        case .unread: "Unread reply"
        }
    }

    /// The symbol drawn before the word.
    var systemImage: String {
        switch self {
        case .writing: "ellipsis"
        case .unread: "circle.fill"
        }
    }
}

// The list's two marks. A reply can now end while nobody is looking, since a
// run goes on without this device, and the list is where that is said. The
// unread mark is kept with the conversation in the store, so it outlives the
// app being closed; nothing else about it leaves this device, and no log line
// mentions it.
extension AppModel {
    /// The mark a conversation's row shows, or nil for none. Writing wins over
    /// unread: a conversation with a reply in flight is not waiting to be read.
    public func mark(for conversation: Conversation) -> ConversationMark? {
        if isStreaming(conversation.id) || conversation.messages.contains(where: \.isBeingWritten) {
            return .writing
        }
        return conversation.hasUnreadReply ? .unread : nil
    }

    /// Marks a conversation whose reply has just ended as unread, unless it
    /// is the one open. A reply walking away from its run has not ended, and
    /// its caller does not come here.
    func markUnreadUnlessOpen(_ conversation: inout Conversation) {
        guard conversation.id != selectedConversationID else { return }
        conversation.hasUnreadReply = true
    }

    /// Opening a conversation clears its mark. Its place in the list, and the
    /// time it was last changed, stay as they were.
    func markRead(_ id: UUID?) {
        guard let id, var conversation = conversations.first(where: { $0.id == id }), conversation.hasUnreadReply
        else { return }
        conversation.hasUnreadReply = false
        update(conversation)
    }
}
