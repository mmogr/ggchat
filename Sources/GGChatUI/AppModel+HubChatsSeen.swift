import Foundation
import GGChatCore

// What a Mac's section says when the Mac cannot be reached: the titles its
// list last showed, and when. They are kept on the provider's row, as its
// last-heard time is, so they outlive a relaunch and go when the provider
// does. No text of a chat is kept (ADR 0007).
extension AppModel {
    /// Whether a paired Mac's chats can be read now: its pipe is up.
    public func hubIsReachable(_ providerID: UUID) -> Bool {
        pipeSessions[providerID] != nil && pipeStatuses[providerID]?.isConnected == true
    }

    /// A Mac's chat is marked Writing while the Mac, reachable, holds a reply
    /// to it not yet saved. It is never New: this phone keeps nothing of the
    /// chat to compare with.
    public func mark(for chat: HubChatSummary, on providerID: UUID) -> ConversationMark? {
        guard hubIsReachable(providerID), chat.liveRun != nil else { return nil }
        return .writing
    }

    /// The line under a Mac's section, when there is something to say: that
    /// it does not share its chats, when its titles were last seen while it
    /// cannot be reached, or that it has none.
    public func hubLine(for providerID: UUID, locale: Locale, calendar: Calendar) -> String? {
        guard let config = providers.first(where: { $0.id == providerID }) else { return nil }
        if hubNotShared.contains(providerID) { return "\(config.name) does not share its chats with this phone." }
        guard hubIsReachable(providerID) else {
            guard let seen = hubSeenAt[providerID] else { return "not seen yet" }
            return "last seen \(Self.shortStamp(seen, now: now(), locale: locale, calendar: calendar))"
        }
        if hubChats[providerID]?.isEmpty == true { return "No chats on \(config.name) yet." }
        return nil
    }

    /// Reads the titles each paired Mac's list last showed. One that will not
    /// read costs its section's titles, not the launch.
    func loadSeenHubChats() {
        for config in providers where config.isPipe {
            do {
                guard let seen = try store.loadHubChats(forProvider: config.id) else { continue }
                hubChats[config.id] = seen.chats.map {
                    HubChatSummary(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
                }
                hubSeenAt[config.id] = seen.seenAt
            } catch {
                log.log(.error, "could not read \(config.name)'s chat titles (\(StoreDirectory.describe(error)))")
            }
        }
    }

    /// Keeps the titles a list just read, and when.
    func keepSeen(_ chats: [HubChatSummary], from config: ProviderConfig) {
        let stamp = now()
        hubSeenAt[config.id] = stamp
        let seen = chats.map { SeenHubChat(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
        do {
            try store.save(hubChats: seen, seenAt: stamp, forProvider: config.id)
        } catch {
            log.log(.error, "could not keep \(config.name)'s chat titles (\(StoreDirectory.describe(error)))")
        }
    }
}
