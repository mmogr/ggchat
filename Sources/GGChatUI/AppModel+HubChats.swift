import Foundation
import GGChatCore

/// What the list selects: a conversation kept on this phone, or a chat a
/// paired Mac holds, read live and never kept here.
public enum SidebarSelection: Hashable, Sendable {
    case local(UUID)
    case hub(providerID: UUID, chatID: Int64)
}

/// How a paired Mac's last list went, for as long as the app runs.
enum HubListOutcome: Equatable {
    /// It listed: its section shows its chats live while its pipe is up.
    case listed
    /// It reads its chats only to a device through its tunnel.
    case notShared
    /// Its gglib has no chats route (404): the section is hidden until a
    /// list works.
    case tooOld
    /// It could not be read: the section shows what it last saw, and when.
    case failed
}

/// A paired Mac's chat, open: its rows read live into memory, dropped when
/// it is no longer selected, and never written to the store.
public struct OpenHubChat: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case reading
        /// Its rows, as this phone draws them.
        case read([Message])
        /// Why there are no rows: the Mac is unreachable, or said no.
        case unavailable(String)

        /// Whether rows are on screen.
        var showsRows: Bool {
            if case .read = self { return true }
            return false
        }
    }

    public let providerID: UUID
    public let chatID: Int64
    public let title: String
    public internal(set) var state: State
    /// Why the last send went nowhere, or how the last reply ended badly.
    public internal(set) var notice: String?
}

// "On home" in the list: each paired Mac's chats, read live through its pipe.
// No text of a Mac's chats goes into the store: the list lives in memory,
// but for the titles `AppModel+HubChatsSeen` keeps, and an opened chat's
// rows live only while it is selected. A server
// added by address has no section, because gglib reads its chats only to a
// device through its tunnel.
extension AppModel {
    /// The list's selection: a local conversation, as `selectedConversationID`
    /// holds it, or a Mac's chat. Choosing one drops the other; choosing
    /// nothing, as Back does on a phone, drops both.
    public var selection: SidebarSelection? {
        get {
            if let id = selectedConversationID { return .local(id) }
            return openedHubChat.map { .hub(providerID: $0.providerID, chatID: $0.chatID) }
        }
        set {
            switch newValue {
            case .local(let id)?:
                dropHubChat()
                selectedConversationID = id
            case .hub(let providerID, let chatID)?:
                openHubChat(chatID, on: providerID)
            case nil:
                dropHubChat()
                selectedConversationID = nil
            }
        }
    }

    /// The providers with a section of their own: the paired Macs, but for
    /// one whose gglib is too old to have chats.
    public var hubProviders: [ProviderConfig] {
        providers.filter { $0.isPipe && hubListOutcome[$0.id] != .tooOld }
    }

    /// Lists every paired Mac's chats: through a pipe that is up at once, and
    /// through one that is not once a quiet dial brings it up. At launch, and
    /// on a pull of the list. A Mac with no section is asked too, since its
    /// gglib may have been updated. The way to the background stops it
    /// between Macs, as it stops `resumeEveryPipe`.
    public func refreshHubChats() async {
        for config in providers where config.isPipe {
            guard !Task.isCancelled, !isAway else { return }
            if pipeSessions[config.id] == nil {
                await connectPipe(for: config, quietly: true)
            }
            await listHubChats(config.id)
        }
    }

    /// A pipe came up: its Mac's chats are listed again, and its chat on
    /// screen read again if it could not be.
    func hubPipeCameUp(_ providerID: UUID) {
        Task { await listHubChats(providerID) }
        if let open = openedHubChat, open.providerID == providerID, open.state != .reading || hubReading == nil {
            readHubChat()
        }
        readOnHubReply()
    }

    /// Lists one Mac's chats, when its pipe is up, and keeps the list in
    /// memory. A failure keeps what was there, and is logged by its kind.
    func listHubChats(_ providerID: UUID) async {
        guard let config = providers.first(where: { $0.id == providerID }), let hub = reachableHubChats(for: config),
            !hubListing.contains(providerID)
        else { return }
        hubListing.insert(providerID)
        defer { hubListing.remove(providerID) }
        let unread = unreadHubReplies(providerID)
        do {
            let list = try await hub.listChats()
            guard providers.contains(where: { $0.id == providerID }) else { return }
            hubChats[providerID] = list.chats
            settleHubReplies(unread, by: list)
            hubListOutcome[providerID] = .listed
            keepSeen(list.chats, from: config)
        } catch {
            // What was seen stays, in memory and in the store.
            guard providers.contains(where: { $0.id == providerID }) else { return }
            switch error {
            case .notShared: hubListOutcome[providerID] = .notShared
            case .notFound: hubListOutcome[providerID] = .tooOld
            case .refused, .dropped: hubListOutcome[providerID] = .failed
            }
            log.log(.info, "\(config.name) did not list its chats: \(Self.kind(of: error))")
        }
    }

    /// Opens a Mac's chat, reading its rows live. Again on the chat already
    /// open does nothing.
    func openHubChat(_ chatID: Int64, on providerID: UUID) {
        guard openedHubChat?.providerID != providerID || openedHubChat?.chatID != chatID,
            providers.contains(where: { $0.id == providerID })
        else { return }
        dropHubChat()
        selectedConversationID = nil
        let title = hubChats[providerID]?.first { $0.id == chatID }?.title ?? ""
        openedHubChat = OpenHubChat(providerID: providerID, chatID: chatID, title: title, state: .reading)
        readHubChat()
        readOnHubReply()
    }

    /// A dial ended: the open chat that waited for it, and was not read
    /// because its pipe never came up, says its Mac is unreachable.
    func settleHubChat(_ providerID: UUID) {
        guard let open = openedHubChat, open.providerID == providerID, open.state == .reading, hubReading == nil
        else { return }
        readHubChat()
    }

    /// Reads the open chat's rows, or says why it cannot. A dial in flight is
    /// waited for: its pipe coming up reads again. Rows already on screen
    /// stay there until the new ones land.
    func readHubChat() {
        guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }) else {
            return
        }
        hubReading?.cancel()
        hubReading = nil
        guard let hub = reachableHubChats(for: config) else {
            if open.state.showsRows { return }
            let why = hubIsUnpaired(config.id) ? unpairedLine(config) : "\(config.name) is unreachable."
            openedHubChat?.state = connecting.contains(config.id) ? .reading : .unavailable(why)
            return
        }
        if !open.state.showsRows { openedHubChat?.state = .reading }
        hubReading = Task { [weak self] in
            let answer: Result<HubChatOpen, HubChatsFailure>
            do throws(HubChatsFailure) {
                answer = .success(try await hub.openChat(id: open.chatID))
            } catch {
                answer = .failure(error)
            }
            guard !Task.isCancelled else { return }
            self?.show(answer, of: open, from: config)
        }
    }

    /// Puts what the Mac sent on screen, if its chat is still the one open.
    private func show(_ answer: Result<HubChatOpen, HubChatsFailure>, of open: OpenHubChat, from config: ProviderConfig)
    {
        guard openedHubChat?.providerID == open.providerID, openedHubChat?.chatID == open.chatID else { return }
        hubReading = nil
        switch answer {
        case .success(let chat):
            openedHubChat?.state = .read(Self.rows(of: chat, at: now()))
            dropEndedHubReplies(open.chatID, on: open.providerID)
        case .failure(.notShared):
            openedHubChat?.state = .unavailable("\(config.name) does not share its chats with this phone.")
        case .failure(.notFound):
            openedHubChat?.state = .unavailable("\(config.name) no longer has this chat.")
        case .failure(let failure):
            log.log(.info, "\(config.name) did not send a chat: \(Self.kind(of: failure))")
            // A read again under rows already shown keeps them.
            if openedHubChat?.state.showsRows == true { return }
            openedHubChat?.state = .unavailable("\(config.name) did not send this chat. Try again in a moment.")
        }
    }

    /// The rows this phone draws: the questions and the replies with words
    /// in them. The system prompt, tool results and a reply that only called
    /// tools are the Mac's to show.
    static func rows(of chat: HubChatOpen, at stamp: Date) -> [Message] {
        chat.messages.compactMap { row in
            guard let role = Role(rawValue: row.role), role != .system, !row.content.isEmpty else { return nil }
            return Message(role: role, content: row.content, createdAt: stamp)
        }
    }

    /// Drops the open chat and the read under way, keeping nothing.
    func dropHubChat() {
        if let open = openedHubChat { detachHubReply(open.chatID, on: open.providerID) }
        hubReading?.cancel()
        hubReading = nil
        openedHubChat = nil
    }

    /// Forgets a removed provider's chats.
    func forgetHubChats(_ providerID: UUID) {
        hubChats[providerID] = nil
        hubSeenAt[providerID] = nil
        hubListOutcome[providerID] = nil
        if openedHubChat?.providerID == providerID { dropHubChat() }
        forgetHubReplies(providerID)
    }

    /// The provider as a hub whose chats can be read now: a paired Mac whose
    /// pipe is up.
    func reachableHubChats(for config: ProviderConfig) -> (any HubChatsProvider)? {
        guard config.isPipe, hubIsReachable(config.id) else { return nil }
        return makeProvider(for: config) as? any HubChatsProvider
    }

    /// A failure's kind for a log line, which names nothing the Mac sent.
    private static func kind(of failure: HubChatsFailure) -> String {
        switch failure {
        case .notShared: "not shared"
        case .notFound: "not found"
        case .refused(let error): "refused, \(error.code ?? "no code")"
        case .dropped(let error): "dropped, \(error?.code ?? "no code")"
        }
    }
}
