import Foundation
import GGChatCore

// Walking away from a reply a Mac is writing to its chat, and reading on.
// Leaving the chat, or the background, walks away: the Mac goes on writing,
// the reply is kept in memory with its cursor, and its run's id and chat are
// kept on the provider's row. Opening the chat again, coming back, and its
// pipe coming up read on from the cursor; a launch, which has none of the
// text, reads the run from its start. As for this device's own replies (ADR
// 0002), a reading that got nothing reads on after a pause, a few times.
extension AppModel {
    /// Reads on from the chat open's reply, when nobody is reading it, the
    /// app is in front, and its Mac can be reached. A turn whose `PUT` was
    /// never answered is put again under its id first.
    func readOnHubReply() {
        guard !isAway, let reply = openHubReply, !reply.ended, reply.reading == nil,
            let config = providers.first(where: { $0.id == reply.providerID }),
            let hub = reachableHubChats(for: config)
        else { return }
        reply.reading = Task { [weak self] in
            guard let self else { return }
            if reply.started {
                await readTurn(reply, on: hub, config)
            } else {
                await putTurn(reply, on: hub, config)
            }
        }
    }

    /// The reading stopped before the run ended: the reply is kept, and read
    /// on at once if the reading got somewhere, or after a pause if not.
    func walkAway(_ reply: HubLiveReply, readAny: Bool) {
        reply.reading = nil
        if readAny {
            readOnAttempts[reply.key] = nil
            return readOnHubReply()
        }
        readOnAfterAPause(reply.key) { $0.readOnHubReply() }
    }

    /// On the way to the background: every reply being read is walked away
    /// from, and waited for.
    func detachHubReplies() async {
        for reply in hubReplies {
            guard let reading = reply.reading else { continue }
            reply.detaching = true
            reading.cancel()
            await reading.value
        }
    }

    /// Keeps the runs of a Mac's replies that have started and not ended on
    /// its provider's row, over the ones before.
    func keepHubRuns(_ providerID: UUID) {
        let runs = hubReplies.filter { $0.providerID == providerID && $0.started && !$0.ended }
            .map { HeldHubRun(runID: $0.runID, chatID: $0.chatID) }
        do {
            try store.save(hubRuns: runs, forProvider: providerID)
        } catch {
            log.log(.error, "could not keep a Mac's runs (\(StoreDirectory.describe(error)))")
        }
    }

    /// At launch: the replies each paired Mac was writing when the app last
    /// ran. Their text was never kept, so each is read from its start.
    func loadHeldHubRuns() {
        for config in providers where config.isPipe {
            do {
                for run in try store.loadHubRuns(forProvider: config.id) {
                    let reply = HubLiveReply(
                        providerID: config.id, chatID: run.chatID, runID: run.runID, question: nil)
                    reply.started = true
                    hubReplies.append(reply)
                }
            } catch {
                log.log(.error, "could not read \(config.name)'s runs (\(StoreDirectory.describe(error)))")
            }
        }
    }

    /// The replies to a Mac's chats that nobody is reading, as a list of
    /// them is asked for, those whose turn was lost on the way included.
    func unreadHubReplies(_ providerID: UUID) -> [HubLiveReply] {
        hubReplies.filter { $0.providerID == providerID && !$0.ended && $0.reading == nil }
    }

    /// A list the Mac sent after these replies were walked away from: one
    /// whose chat no longer names its run as live has ended, or its lost turn
    /// never arrived, and is forgotten, its rows read when its chat is open.
    /// A lost turn the list names as live did arrive, and is kept as started.
    func settleHubReplies(_ replies: [HubLiveReply], by list: HubChatList) {
        for reply in replies where reply.reading == nil && !reply.ended {
            let live = list.chats.first { $0.id == reply.chatID }?.liveRun
            guard live == reply.runID else {
                endHubReply(reply)
                continue
            }
            if !reply.started {
                reply.started = true
                keepHubRuns(reply.providerID)
            }
        }
    }
}
