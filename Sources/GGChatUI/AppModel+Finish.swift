import Foundation
import GGChatCore

// How a reply in flight is written into its conversation when it ends, is
// put down, or walks away from a run the hub goes on writing.
extension AppModel {
    /// Writes what arrived into the conversation. `refusal` is a failure this
    /// app worked out rather than one a provider reported — a refused dial's
    /// sentence, or a run the hub no longer has — kept where a provider's
    /// error would be, and not counted as one.
    ///
    /// `keepsRun` is a reply walking away from its run: whatever has arrived,
    /// nothing at all included, is written with the run's id and cursor, so
    /// the hub can be read on from there. See `AppModel+Runs`.
    func finish(
        _ live: LiveReply, finished: Bool, cancelled: Bool, refusal: Failure? = nil, keepsRun: Bool = false
    ) {
        defer {
            // Only the reply in flight is cleared: a run given up while it is
            // not being read is finished through here too, beside another.
            if liveReply === live {
                liveReply = nil
                streamTask = nil
            }
        }
        guard var conversation = conversations.first(where: { $0.id == live.conversationID }) else { return }
        let stamp = now()
        // A stop or a background is not a failure, however the provider put
        // it: a cancelled request can surface as a transport error, and
        // whether that arrives before the stream ends is a race. Nor is it a
        // transport error after a resume, for the diagnostics below.
        let error = cancelled ? nil : live.error
        let failure = refusal ?? error.map(Failure.init)
        // gglib's notice of that failure, written as text before the error
        // itself. The error is drawn, so the notice is not kept as a reply.
        let content = error != nil && Self.isAProxyNotice(live.content) ? "" : live.content
        // A run whose start was never answered keeps no cursor, which is what
        // tells the next reach to send its `PUT` again.
        let run = keepsRun ? live.runID.map { (id: $0, cursor: live.started ? live.cursor : nil) } : nil
        if let continuingID = live.continuingMessageID,
            let index = conversation.messages.firstIndex(where: { $0.id == continuingID })
        {
            let ending = Ending(
                content: content, reasoning: live.reasoning, finished: finished, failure: failure, run: run)
            write(ending, at: index, in: &conversation)
        } else if run != nil || !content.isEmpty || !live.reasoning.isEmpty || finished {
            conversation.messages.append(
                Message(
                    role: .assistant, content: content,
                    reasoning: live.reasoning.isEmpty ? nil : live.reasoning,
                    isPartial: !finished, failure: failure, createdAt: stamp, runID: run?.id, runCursor: run?.cursor))
        } else if let failure {
            // Nothing arrived and something said why. With no reply to put
            // the sentence under, it goes on the question.
            putOnTheQuestion(failure, in: &conversation)
        }
        if !keepsRun { markUnreadUnlessOpen(&conversation) }
        conversation.updatedAt = stamp
        diagnostics.recordStreamEnd(with: error, at: stamp)
        if let providerID = conversation.providerID {
            if finished { heard(providerID) } else if let error { note(error, from: providerID) }
        }
        if let error {
            streamErrors[conversation.id] = error
            log.log(.error, "stream ended with \(error.code ?? "no code"): \(error.whereToLook)")
        }
        update(conversation)
    }

    /// Adds what arrived to the message it streamed into. A reply left with
    /// nothing in it, which only a run's placeholder can be, is not kept: its
    /// failure, if it has one, goes on the question instead.
    private func write(_ ending: Ending, at index: Int, in conversation: inout Conversation) {
        var message = conversation.messages[index]
        message.content += ending.content
        if !ending.reasoning.isEmpty {
            message.reasoning = (message.reasoning ?? "") + ending.reasoning
        }
        message.isPartial = !ending.finished
        message.failure = ending.failure
        message.runID = ending.run?.id
        message.runCursor = ending.run?.cursor
        guard ending.run == nil, !ending.finished, message.content.isEmpty, message.reasoning?.isEmpty ?? true
        else {
            conversation.messages[index] = message
            return
        }
        conversation.messages.remove(at: index)
        if let failure = ending.failure { putOnTheQuestion(failure, in: &conversation) }
    }

    /// Puts a failure on the last message when it is the question.
    private func putOnTheQuestion(_ failure: Failure, in conversation: inout Conversation) {
        guard let last = conversation.messages.indices.last, conversation.messages[last].role == .user else { return }
        conversation.messages[last].failure = failure
    }

    /// Whether a reply is nothing but gglib's own notice of a failure, which
    /// it writes as ordinary text before the error itself, for clients that
    /// cannot draw an error inside a stream (`gglib-proxy/src/forward.rs`,
    /// `visible_content_frame`). This app draws the error, so when a stream
    /// ended with one the notice is dropped. Kept, it would be the reply, and
    /// Continue would send it back to the model as the start of one.
    ///
    /// The marker is `[proxy] `, space included, within the first three
    /// characters: the notice starts with an emoji, which is one `Character`
    /// however many bytes it takes. The space matters. gglib's
    /// reasoning-only notice reads `[proxy: reasoning-only response]` and is
    /// followed by real output from the model, which must never be dropped.
    /// Every notice this matches is written before generation starts, so no
    /// text from the model can come before one.
    static func isAProxyNotice(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = trimmed.range(of: "[proxy] ") else { return false }
        return trimmed.distance(from: trimmed.startIndex, to: marker.lowerBound) <= 3
    }
}

/// What a reply in flight leaves in the message it streamed into.
private struct Ending {
    var content: String
    var reasoning: String
    var finished: Bool
    var failure: Failure?
    var run: (id: String, cursor: UInt32?)?
}
