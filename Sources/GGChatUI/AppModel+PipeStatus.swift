import Foundation
import GGChatCore

/// The pipe's status, its reason, and the one writer of both.
///
/// Split from `AppModel+Pipe` when pairing stopped hanging up the pipe it
/// redeemed a code over: the dial half of that file grew an install shared
/// with pairing, and this half — what a status means once a session is
/// installed, and the counting that goes with it — reads on its own. Nothing
/// here is `private`: `private` in Swift is per-file even between two
/// extensions of one type, and the install's status task calls both
/// ``announce(_:for:)`` and ``forgetSessionIfCurrent(_:generation:)``.
extension AppModel {
    /// Says why a pipe went away — once, and only when the app did not ask it
    /// to.
    ///
    /// Through the alert rather than the sentence under a partial reply. That
    /// second channel exists only while a partial assistant message is the
    /// last one on screen, so a pipe that dies while an older conversation is
    /// open has nothing to hang a sentence under — and that is the ordinary
    /// case, not the exceptional one. It is also typed `ProviderError`, which
    /// would put a connection sentence behind "Could not reach the server:", a
    /// prefix about a request nobody made.
    ///
    /// `lastError == nil` is the rule `makePipeProvider(for:)` already
    /// follows: never written over the top of a sentence still waiting to be
    /// read. A close the app performed says nothing at all, which is what
    /// keeps a walk to the background silent.
    func announce(_ reason: PipeCloseReason, for config: ProviderConfig) {
        guard reason.wasUnexpected, let sentence = reason.sentence(naming: config.name) else { return }
        log.log(.info, "\(config.name): \(sentence)")
        if lastError == nil { lastError = sentence }
    }

    /// Why the pipe behind a provider last closed, while it is closed.
    public func pipeCloseReason(for providerID: UUID) -> PipeCloseReason? {
        pipeCloseReasons[providerID]
    }

    /// Drops a finished session, unless a newer dial has already replaced it.
    func forgetSessionIfCurrent(_ providerID: UUID, generation: Int) {
        guard dialGeneration[providerID] == generation else { return }
        pipeSessions[providerID] = nil
    }

    /// The one place `pipeStatuses` is written, and so the one place a close
    /// is counted. Being shown as closed and being counted as a close are the
    /// same event; they used to be two.
    ///
    /// ADR 0002's denominator was kept where a status was *observed*, which
    /// is only what a live session sends. The two closes that come from this
    /// side set the pill and told the counter nothing: a dial that was
    /// refused, and the hang-up on the way to the background. The second is
    /// the phone's commonest close by a distance, so the reading was shown
    /// over a denominator that omitted the case it exists to measure.
    ///
    /// `previous != .closed` is what stops one close being counted twice: a
    /// refused dial leaves `.closed` behind, and the background that follows
    /// it hangs up a provider with nothing left to hang up.
    ///
    /// The reason travels through here rather than beside it, and is
    /// *assigned* rather than merged: a reason left behind by an earlier close
    /// would be a sentence about the wrong event. `nil` is therefore the right
    /// answer for every close this side performs — the hang-up on the way to
    /// the background, the manual reconnect, a provider deleted — because a
    /// close the app asked for has nothing to explain.
    func setPipeStatus(
        _ status: PipeStatus?, for providerID: UUID, cutShort: Bool = false,
        because reason: PipeCloseReason? = nil
    ) {
        let previous = pipeStatuses[providerID]
        pipeStatuses[providerID] = status
        pipeCloseReasons[providerID] = status == .closed ? reason : nil
        if status == .closed, previous != .closed {
            let midReply = cutShort || streamingProviderID == providerID
            diagnostics.recordClosed(whileStreaming: midReply)
            log.log(.info, "pipe closed\(midReply ? " mid-reply" : "")\(reason.map { ": \($0)" } ?? "")")
        }
        if status?.isConnected == true, previous?.isConnected != true {
            connectedPulse &+= 1
            // Any answer the status probe kept came from before this
            // connection, through a session not answering yet or an earlier
            // one, and so is any answer still on its way. The chat view asks
            // again on the pulse.
            proxyStatusAvailability[providerID] = nil
            probeGeneration[providerID] = (probeGeneration[providerID] ?? 0) + 1
        }
    }

    /// The provider the reply in flight is going through, if there is one.
    ///
    /// Not `private`: the hang-up pass reads it, and it lives in
    /// `AppModel+Lifecycle` — a different file, which is what `private` means
    /// in Swift even for two extensions of the same type.
    var streamingProviderID: UUID? {
        liveReply.flatMap { live in
            conversations.first { $0.id == live.conversationID }?.providerID
        }
    }
}
