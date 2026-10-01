import Foundation
import GGChatCore

// What a Mac's section says when its chats cannot be read live: the titles
// its list last showed, and when. They are kept on the provider's row, as its
// last-heard time is, so they outlive a relaunch and go when the provider
// does. No text of a chat is kept (ADR 0007).
extension AppModel {
    /// Whether a paired Mac's chats can be read now: its pipe is up.
    public func hubIsReachable(_ providerID: UUID) -> Bool {
        pipeSessions[providerID] != nil && pipeStatuses[providerID]?.isConnected == true
    }

    /// Whether a paired Mac's section shows its chats live: its pipe is up
    /// and its last list worked.
    func hubIsLive(_ providerID: UUID) -> Bool {
        hubIsReachable(providerID) && hubListOutcome[providerID] == .listed
    }

    /// Whether this device has nothing left to dial a paired Mac with: its
    /// ticket or token is not in the Keychain. A Keychain that cannot be read
    /// says nothing either way.
    func hubIsUnpaired(_ providerID: UUID) -> Bool {
        do {
            return try secrets.secret(.ticket, for: providerID) == nil
                || secrets.secret(.token, for: providerID) == nil
        } catch {
            return false
        }
    }

    func unpairedLine(_ config: ProviderConfig) -> String {
        "\(config.name) is not paired with this phone any more. Pair again from the Mac."
    }

    /// A Mac's chat is marked Writing while this phone holds a reply the Mac
    /// is writing to it, reachable or not, and while its section is live and
    /// the Mac says it holds a reply not yet saved. It is never New: this
    /// phone keeps nothing of the chat to compare with.
    public func mark(for chat: HubChatSummary, on providerID: UUID) -> ConversationMark? {
        if hubReply(for: chat.id, on: providerID)?.ended == false { return .writing }
        guard hubIsLive(providerID), chat.liveRun != nil else { return nil }
        return .writing
    }

    /// The line under a Mac's section, when there is something to say: that
    /// this device is no longer paired with it, that it does not share its
    /// chats, when its titles were last seen while they cannot be read live,
    /// or that it has none.
    public func hubLine(for providerID: UUID, locale: Locale, calendar: Calendar) -> String? {
        guard let config = providers.first(where: { $0.id == providerID }) else { return nil }
        if !hubIsReachable(providerID), hubIsUnpaired(providerID) { return unpairedLine(config) }
        if hubListOutcome[providerID] == .notShared {
            return "\(config.name) does not share its chats with this phone."
        }
        guard hubIsLive(providerID) else {
            guard let seen = hubSeenAt[providerID] else { return "not seen yet" }
            return "last seen \(Self.shortStamp(seen, now: now(), locale: locale, calendar: calendar))"
        }
        if hubChats[providerID]?.isEmpty == true { return "No chats on \(config.name) yet." }
        return nil
    }

    /// When a Mac's chat last changed, for its row: "09:13" today, the date
    /// and the time before, and nothing when the Mac's time cannot be read.
    public func stamp(for chat: HubChatSummary, locale: Locale, calendar: Calendar) -> String? {
        Self.hubRowStamp(chat.updatedAt, now: now(), locale: locale, calendar: calendar)
    }

    static func hubRowStamp(_ updatedAt: String, now: Date, locale: Locale, calendar: Calendar) -> String? {
        HubChatSummary.date(fromUpdatedAt: updatedAt).map {
            shortStamp($0, now: now, locale: locale, calendar: calendar)
        }
    }

    /// Reads the titles each paired Mac's list last showed. One that will not
    /// read costs its section's titles, not the launch.
    func loadSeenHubChats() {
        loadHeldHubRuns()
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
