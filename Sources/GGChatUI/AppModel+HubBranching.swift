import Foundation
import GGChatCore

/// Edit, regenerate and Branch from here on a paired Mac's chat open
/// (ADR 0010). The change is sent to the Mac, which makes it by the same
/// rules and keeps any branch it makes as one of its chats; this phone then
/// opens the chat the Mac names and, when the Mac says so, sends the turn
/// that answers its last question. Nothing of the chat is kept here
/// (ADR 0007).
extension AppModel {
    /// What a turn's menu offers on the chat open, `edit` opening the editor
    /// on the turn.
    func hubMessageChanges(edit: @escaping (Message) -> Void) -> MessageChanges {
        MessageChanges(
            edit: edit, regenerate: { [weak self] in self?.regenerateHubMessage($0) },
            branch: { [weak self] in self?.branchHubChat(from: $0) })
    }

    /// Asks a question of the chat open again in other words, keeping its
    /// images, or keeps a reply as written. Blank text changes nothing.
    @discardableResult
    func editHubMessage(_ messageID: UUID, to text: String) -> Task<Void, Never>? {
        guard case .read(let rows) = openedHubChat?.state else { return nil }
        guard let message = rows.first(where: { $0.id == messageID }) else {
            openedHubChat?.notice = Self.sentence(for: .messageNotFound)
            return nil
        }
        guard let content = message.edited(to: text) else { return nil }
        let images = message.role == .user ? message.images.map(\.id) : []
        return changeHubChat(messageID) { .edit(messageID: $0, content: content, images: images) }
    }

    /// Answers again, on a new branch on the Mac, the question a reply of
    /// the chat open answers.
    @discardableResult
    func regenerateHubMessage(_ messageID: UUID) -> Task<Void, Never>? {
        changeHubChat(messageID) { .regenerate(messageID: $0) }
    }

    /// Copies the chat open, as far as the end of the turn holding the
    /// message, into a new chat on the Mac to go on in. Nothing is answered.
    @discardableResult
    func branchHubChat(from messageID: UUID) -> Task<Void, Never>? {
        changeHubChat(messageID) { .branch(messageID: $0) }
    }

    /// Opens another of the Mac's chats of the family: an option at a branch
    /// point of the chat open.
    func openHubBranch(_ chatID: Int64) {
        guard let open = openedHubChat else { return }
        selection = .hub(providerID: open.providerID, chatID: chatID)
    }

    /// Answers the question the chat open ends in, which nothing answers:
    /// the turn a change leaves, or one whose answer never started.
    @discardableResult
    func answerHubChat() -> Task<Void, Never>? {
        guard let open = openedHubChat, open.answerable, let mac = hubForChange(open) else { return nil }
        return answerHubChat(open.chatID, thinking: open.thinking.change, on: mac.hub, mac.config)
    }

    /// Sends the change naming the Mac's row the message shows.
    private func changeHubChat(
        _ messageID: UUID, _ change: (Int64) -> ChatChange<Int64>
    ) -> Task<Void, Never>? {
        guard let open = openedHubChat else { return nil }
        guard let rowID = open.rowIDs[messageID] else {
            openedHubChat?.notice = Self.sentence(for: .messageNotFound)
            return nil
        }
        guard let mac = hubForChange(open) else { return nil }
        let (config, hub) = mac
        openedHubChat?.changing = true
        let body = HubChatChange(change(rowID))
        return Task { [weak self] in
            let changed: HubChatChanged
            do throws(HubChatsFailure) {
                changed = try await hub.changeChat(id: open.chatID, change: body)
            } catch {
                self?.refuseHubChange(error, on: open, config)
                return
            }
            await self?.showHubChange(changed, of: open, on: hub, config)
        }
    }

    /// The chat's Mac, to change the chat or answer it now. Refused while
    /// the chat has a reply being written or a change on its way, and when
    /// its Mac cannot be reached, each with a sentence in the view.
    private func hubForChange(_ open: OpenHubChat) -> (config: ProviderConfig, hub: any HubChatsProvider)? {
        guard let config = providers.first(where: { $0.id == open.providerID }) else { return nil }
        if openHubChatIsWriting || open.changing {
            openedHubChat?.notice = Self.busyLine(config)
            return nil
        }
        guard let hub = reachableHubChats(for: config) else {
            openedHubChat?.notice = "\(config.name) is unreachable."
            return nil
        }
        openedHubChat?.notice = nil
        return (config, hub)
    }

    /// Whether the chat open is still the one a change was asked of.
    private func stillOpen(_ open: OpenHubChat) -> Bool {
        openedHubChat?.providerID == open.providerID && openedHubChat?.chatID == open.chatID
    }

    /// Opens the chat the change left, a new branch or the chat open read
    /// again, and answers its last question when the Mac says to. A change
    /// whose chat was left meanwhile is shown only in the list.
    private func showHubChange(
        _ changed: HubChatChanged, of open: OpenHubChat, on hub: any HubChatsProvider, _ config: ProviderConfig
    ) async {
        if stillOpen(open) {
            openedHubChat?.changing = false
            if changed.forked {
                openHubChat(changed.conversationID, on: open.providerID)
            } else {
                readHubChat()
            }
            if changed.answer {
                answerHubChat(changed.conversationID, thinking: open.thinking.change, on: hub, config)
            }
        }
        await listHubChats(open.providerID)
    }

    /// Starts the turn that answers a chat's last question, saying the
    /// Thinking choice of the chat it was asked from. It is drawn under the
    /// rows once they land, as a send's reply is.
    @discardableResult
    private func answerHubChat(
        _ chatID: Int64, thinking: HubThinking?, on hub: any HubChatsProvider, _ config: ProviderConfig
    ) -> Task<Void, Never> {
        dropEndedHubReplies(chatID, on: config.id)
        let reply = HubLiveReply(
            providerID: config.id, chatID: chatID, runID: UUID().uuidString, question: "", thinking: thinking,
            answersSaved: true)
        hubReplies.append(reply)
        let task = Task { [weak self] in
            guard let self else { return }
            await putTurn(reply, on: hub, config)
        }
        reply.reading = task
        return task
    }

    /// Why the Mac did not make the change, in the view: its rules' sentence
    /// when it refused by one of their codes.
    private func refuseHubChange(_ failure: HubChatsFailure, on open: OpenHubChat, _ config: ProviderConfig) {
        log.log(.info, "\(config.name) did not change a chat: \(Self.kind(of: failure))")
        guard stillOpen(open) else { return }
        openedHubChat?.changing = false
        let line: String? =
            switch failure {
            case .notShared: "\(config.name) does not share its chats with this phone."
            case .notFound: "\(config.name) no longer has this chat, or needs updating to change it."
            case .refused(let error):
                if let refusal = Self.branchRefusal(error.code) {
                    Self.sentence(for: refusal)
                } else {
                    "\(config.name) did not make the change. \(error.errorDescription ?? "")"
                        .trimmingCharacters(in: .whitespaces)
                }
            case .dropped: "\(config.name) could not be reached. Try again in a moment."
            }
        if let line { openedHubChat?.notice = line }
    }

    /// The rule a refusal's code names, if it names one.
    static func branchRefusal(_ code: String?) -> BranchRefusal? {
        let rules: [BranchRefusal] = [.messageNotFound, .unchanged, .notAReply, .nothingToAnswer]
        return rules.first { $0.code == code }
    }
}
