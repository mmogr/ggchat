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
    /// app is in front, and its Mac can be reached. Every turn whose `PUT`
    /// was never answered, open or not, is put again under its id first.
    func readOnHubReply() {
        giveBackRefused()
        for reply in hubReplies where !reply.started { putAgain(reply) }
        guard !isAway, let reply = openHubReply, reply.started, !reply.ended, reply.reading == nil,
            let config = providers.first(where: { $0.id == reply.providerID }),
            let hub = reachableHubChats(for: config)
        else { return }
        reply.reading = Task { [weak self] in
            guard let self else { return }
            await readTurn(reply, on: hub, config)
        }
    }

    /// Puts a turn whose `PUT` was never answered again under its id, when
    /// nobody is reading it, the app is in front, and its Mac can be
    /// reached, and while this phone still holds it: a refused one is gone.
    /// The Mac answers a repeated id with the run already there.
    private func putAgain(_ reply: HubLiveReply) {
        guard !isAway, !reply.started, !reply.ended, reply.reading == nil, hubReplies.contains(where: { $0 === reply }),
            let config = providers.first(where: { $0.id == reply.providerID }),
            let hub = reachableHubChats(for: config)
        else { return }
        reply.reading = Task { [weak self] in
            guard let self else { return }
            await putTurn(reply, on: hub, config)
        }
    }

    /// A send refused while its chat was not on screen: why, and its text,
    /// are kept in memory for the chat to give back when it is next opened.
    func keepRefused(_ reply: HubLiveReply, _ why: String) {
        refusedHubSends[reply.providerID, default: [:]][reply.chatID] = (why, reply.question)
    }

    /// Gives the chat open what a refusal kept for it while it was not.
    private func giveBackRefused() {
        guard let open = openedHubChat,
            let refused = refusedHubSends[open.providerID]?.removeValue(forKey: open.chatID)
        else { return }
        openedHubChat?.notice = refused.notice
        openedHubChat?.unsent = refused.text
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

    /// A list the Mac sent after these replies were walked away from: a
    /// started one whose chat no longer names its run as live has ended, and
    /// is forgotten, its rows read when its chat is open. A lost turn the list
    /// names as live did arrive, and is kept as started. One it does not name
    /// is kept, and put again under its id: the Mac names a run only once it
    /// has reserved it, which may wait for a model to load, so only the next
    /// `PUT` can say, and a list says the Mac answers now.
    func settleHubReplies(_ replies: [HubLiveReply], by list: HubChatList) {
        for reply in replies where reply.reading == nil && !reply.ended && hubReplies.contains(where: { $0 === reply })
        {
            let live = list.chats.first { $0.id == reply.chatID }?.liveRun
            if live == reply.runID, !reply.started {
                reply.started = true
                keepHubRuns(reply.providerID)
            } else if live != reply.runID, reply.started {
                endHubReply(reply)
            } else if !reply.started {
                putAgain(reply)
            }
        }
    }
}
