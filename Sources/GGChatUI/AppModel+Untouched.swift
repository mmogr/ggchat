import Foundation
import GGChatCore

// What New conversation starts from. The list keeps at most one untouched
// conversation, the one open (`Conversation.isUntouched(defaultModel:)`):
// New conversation on it is that one again, it goes when another is opened,
// and a launch clears any an older build left behind.
extension AppModel {
    /// The provider a new conversation starts with: see `newConversation()`.
    var providerOfTheOpenConversation: ProviderConfig? {
        let open: UUID? =
            switch selection {
            case .local(let id)?: conversations.first { $0.id == id }?.providerID
            case .hub(let providerID, _)?: providerID
            case nil: nil
            }
        return providers.first { $0.id == open } ?? providers.first
    }

    /// Whether `conversation` holds nothing a person chose and has no reply
    /// in flight, so nothing is lost if it goes.
    func isUntouched(_ conversation: Conversation) -> Bool {
        !isStreaming(conversation.id)
            && conversation.isUntouched(defaultModel: provider(for: conversation)?.defaultModel)
    }

    /// The open conversation, when it is untouched and with `provider`: what
    /// New conversation opens rather than another like it.
    func untouchedOpenConversation(with provider: ProviderConfig?) -> Conversation? {
        guard let open = selectedConversation, open.providerID == provider?.id, isUntouched(open) else {
            return nil
        }
        return open
    }

    /// Deletes every untouched conversation but `next`. Called by the
    /// selection's setter before it moves, so a deletion clears a selection
    /// that is about to be written anyway. Not for no selection at all: Back
    /// on a phone, or a list that briefly reports none, keeps it, and the
    /// next one opened takes it away.
    func dropUntouched(leavingFor next: SidebarSelection?) {
        guard let next else { return }
        let opening: UUID? = if case .local(let id) = next { id } else { nil }
        let left = conversations.filter { $0.id != opening && isUntouched($0) }
        for conversation in left { deleteConversation(conversation.id) }
    }

    /// Deletes every untouched conversation but the open one: those an
    /// older build, which kept each New conversation, left in the list.
    func dropUntouchedLeftBehind() {
        let left = conversations.filter { $0.id != selectedConversationID && isUntouched($0) }
        for conversation in left { deleteConversation(conversation.id) }
    }
}
