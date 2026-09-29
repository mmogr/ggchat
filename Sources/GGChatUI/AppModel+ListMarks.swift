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
//
// Selecting a conversation is not reading it. A launch restores the last
// selection, and a phone can open on the list with it; only the chat view
// says a conversation is shown, from its appear and from a move to another
// conversation. Not from a `.task`, which a collapsed split view on iOS 27
// cancels at birth, and not from its disappear, which the same split view
// sends within a millisecond of the appear while the chat stays on screen
// (see `AppModel+Opening`). Leaving a chat is read from the selection
// instead: going Back to the list on a phone clears it.
extension AppModel {
    /// The mark a conversation's row shows, or nil for none. Writing wins over
    /// unread: a conversation with a reply in flight is not waiting to be read.
    public func mark(for conversation: Conversation) -> ConversationMark? {
        if isStreaming(conversation.id) || conversation.messages.contains(where: \.isBeingWritten) {
            return .writing
        }
        return conversation.hasUnreadReply ? .unread : nil
    }

    /// The chat view of `id` has been shown: if the app is in front, what it
    /// shows has been read.
    public func chatAppeared(_ id: UUID) {
        chatShown = id
        readTheChatOnScreen()
    }

    /// Whether the person can see this conversation's replies now: its chat
    /// was the last shown, it is still the one selected, and the app is in
    /// front.
    func isBeingRead(_ id: UUID) -> Bool {
        chatShown == id && selectedConversationID == id && !isAway
    }

    /// Clears the mark of the conversation on screen, when it is being read:
    /// as its chat appears, and as the app comes back to the front.
    func readTheChatOnScreen() {
        guard let id = chatShown, isBeingRead(id) else { return }
        markRead(id)
    }

    /// Marks a conversation whose reply has just ended as unread, unless it
    /// is being read or the person stopped the reply. A reply walking away
    /// from its run has not ended, and its caller does not come here.
    func markUnreadUnlessRead(_ conversation: inout Conversation, stoppedHere: Bool) {
        guard !stoppedHere, !isBeingRead(conversation.id) else { return }
        conversation.hasUnreadReply = true
    }

    /// Clears a conversation's mark. Its place in the list, and the time it
    /// was last changed, stay as they were.
    func markRead(_ id: UUID) {
        guard var conversation = conversations.first(where: { $0.id == id }), conversation.hasUnreadReply
        else { return }
        conversation.hasUnreadReply = false
        update(conversation)
    }
}
