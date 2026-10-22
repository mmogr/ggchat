import Foundation
import GGChatCore

/// What the app's icon offers when it is held down on the Home Screen: a
/// new conversation, one that opens on the camera, and one with Draw
/// pressed.
enum QuickAction: String, CaseIterable, Sendable {
    case newChat = "new-chat"
    case camera = "new-chat-camera"
    case draw = "new-chat-draw"
}

/// How the composer of a conversation a quick action started begins: read
/// once by that conversation's composer, and by no other.
struct ComposerStart: Equatable {
    let conversation: UUID
    let action: QuickAction
}

extension AppModel {
    /// The quick actions to offer now. None before there is a provider to
    /// talk to; the camera only where there is one; Draw only with a paired
    /// Mac that can draw or has not been asked yet.
    func quickActions(hasCamera: Bool) -> [QuickAction] {
        guard !providers.isEmpty else { return [] }
        return QuickAction.allCases.filter { action in
            switch action {
            case .newChat: true
            case .camera: hasCamera
            case .draw: drawingProvider != nil
            }
        }
    }

    /// Starts a new conversation as `action` asks, and leaves its composer
    /// a note of how to begin. Draw's is with a paired Mac, whichever
    /// provider is open; the others are with the open conversation's
    /// provider, as New conversation's is. Nothing is started with no
    /// provider, or for Draw with no paired Mac: the app opens as it was.
    func perform(_ action: QuickAction) {
        guard let provider = action == .draw ? drawingProvider : providerOfTheOpenConversation else { return }
        enlarged = nil
        let conversation = newConversation(with: provider)
        composerStart = action == .newChat ? nil : ComposerStart(conversation: conversation.id, action: action)
    }

    /// How `conversation`'s composer is to begin, once: nil for any other
    /// conversation, and nil the second time it is asked.
    func takeComposerStart(for conversation: UUID) -> QuickAction? {
        guard let start = composerStart, start.conversation == conversation else { return nil }
        composerStart = nil
        return start.action
    }

    /// The paired Mac a drawing starts with: the first known to be able to
    /// draw, else the first not asked yet, which is asked when its pipe
    /// comes up. One that said it cannot draw is never it.
    private var drawingProvider: ProviderConfig? {
        let paired = providers.filter(\.isPipe)
        return paired.first { drawRefusal(on: $0) == nil } ?? paired.first { drawings[$0.id] == nil }
    }
}
