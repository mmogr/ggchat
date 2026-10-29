import Foundation
import GGChatCore

// When this device's engine runs and when it is put down (ADR 0015). It runs
// in the foreground only: it is served when a conversation on This iPhone
// opens or a send waits for it, it loads a model within the first request
// that names one, and it is put down on the way to the background, on a
// memory warning while no reply is going through it, and by Load again,
// which serves it afresh. Coming back to the foreground starts nothing.
extension AppModel {
    /// The one place `engineStatus` is written, which is what the status
    /// pill shows of the engine. The log lines it writes as a model starts
    /// loading, is ready and fails are the reading ADR 0015 is held to, so a
    /// status written anywhere else would be on the pill and missing from
    /// the reading. `scripts/check_one_status_writer.sh` holds it to that.
    func setEngineStatus(_ status: EngineStatus?) {
        let previous = engineStatus
        engineStatus = status
        switch status {
        case .loading(let model, _)?:
            if case .loading(model, _)? = previous { return }
            log.log(.info, "engine loading \(model)")
        case .ready(let model, let nCtx)? where previous != status:
            log.log(.info, "engine ready with \(model), context \(nCtx)")
        case .failed(let model, let reason)? where previous != status:
            log.log(.error, "engine could not load \(model): \(reason)")
        default: break
        }
    }

    /// Puts the engine down on the way to the background, after the
    /// background pass has put down every reply and waited for them, so a
    /// reply through it keeps what had arrived and offers Continue. Inside
    /// that pass's assertion. Skipped when the app has come back before the
    /// pass got here: in the foreground the engine may run, and a reply sent
    /// since would be cut off.
    func putEngineDownForTheBackground() async {
        guard isAway else { return }
        if engineSession != nil || engineServing != nil { log.log(.info, "engine put down for the background") }
        await shutDownEngine()
    }

    /// The system is short of memory: the engine is put down, and the model
    /// it holds freed, unless a reply is going through it, which would be
    /// cut off. The next send serves it again and loads the model. Returns
    /// the shutdown, so a test can wait on it, or nil when nothing was done.
    @discardableResult
    public func memoryWarning() -> Task<Void, Never>? {
        guard engineSession != nil || engineServing != nil else { return nil }
        if let id = thisIPhoneID, !liveReplies(through: id).isEmpty {
            log.log(.info, "memory warning with a reply going through the engine; the engine stays up")
            return nil
        }
        log.log(.info, "memory warning; engine put down")
        return Task { await shutDownEngine() }
    }

    /// Load again, from the status pill once the engine could not load the
    /// conversation's model: the engine is put down and served afresh, with
    /// this device's memory read again, as Reconnect hangs a pipe up and
    /// dials it again. Then, if the engine is serving, the conversation is
    /// still the one open and its question has no answer, the question is
    /// asked again, which loads the model; otherwise the next send does.
    /// Returns the work, so a test can wait on it.
    @discardableResult
    func loadAgain(_ conversationID: UUID) -> Task<Void, Never> {
        Task {
            await shutDownEngine()
            await serveEngine()
            guard selectedConversationID == conversationID, engineSession != nil, let asking = retry() else { return }
            await asking.value
        }
    }

    /// Notes a reply through This iPhone that the engine refused as too big
    /// for this device, so the pill says "Too big" for that model until the
    /// engine is served again with the memory read afresh.
    func noteEngineRefusal(_ error: ProviderError, of model: String?, in conversation: Conversation) {
        guard error.code == ProviderError.Code.modelDoesNotFit.rawValue, let model,
            provider(for: conversation)?.kind == .onDevice
        else { return }
        onDevice.tooBig.insert(model)
    }
}
