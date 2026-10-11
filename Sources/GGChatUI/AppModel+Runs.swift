import Foundation
import GGChatCore

// A reply to gglib is a run: the hub writes it whether or not this device is
// there to read it (ADR 0002, amended 2026-09-29). Going to the background,
// or losing the connection, walks away from the run and keeps its id and the
// last event read with the message; coming back reads on from there; see
// `AppModel+ReadingOn`. Stop, a deletion, or a hub that refuses to go on
// gives the run up.
extension AppModel {
    /// The provider as a hub to start a run on, or nil when this reply goes
    /// the old way: the provider is not gglib, or has said it has no runs.
    func runHub(_ provider: any Provider, for config: ProviderConfig) -> (any RunProvider)? {
        guard asksForProgress(config), !providersWithoutRuns.contains(config.id) else { return nil }
        return provider as? any RunProvider
    }

    /// Starts the reply as a run under an id minted here, and reads it.
    func startRun(_ request: ChatRequest, on hub: any RunProvider, for config: ProviderConfig, live: LiveReply) async {
        // Set before the request, so a reply put down while it is on its way
        // still names the run it may have started.
        live.runID = UUID().uuidString
        await putRun(request, on: hub, for: config, live: live)
    }

    /// Sends the run's `PUT` and reads the run. Sent again under the same id
    /// when an earlier one was never answered: a hub that has the run answers
    /// 200 and starts nothing. A hub that answers as one without runs is
    /// remembered, and this reply and the rest to it go the old way, with
    /// nothing shown.
    func putRun(_ request: ChatRequest, on hub: any RunProvider, for config: ProviderConfig, live: LiveReply) async {
        guard let id = live.runID else { return }
        let start: RunStart
        do {
            start = try await hub.startRun(id: id, request)
        } catch {
            guard !Task.isCancelled else { return await putDown(live, on: hub) }
            // Lost on the way, and it may have arrived: the id is kept, and
            // the next reach asks again under it.
            if case .transport = error { return walkAway(live, readAny: false) }
            live.runID = nil
            live.error = error
            return finish(live, finished: false, cancelled: false)
        }
        live.started = true
        guard !Task.isCancelled else { return await putDown(live, on: hub) }
        switch start {
        case .started(let info) where info.frames == .unknown:
            // A later gglib's way of writing events: the run is stopped and
            // the reply given up, since reading it would show nothing.
            cancelRun(id, on: hub)
            live.runID = nil
            giveUp(live, saying: "is writing this reply in a way this version of the app cannot read.")
        case .started(let info):
            live.frames = info.frames ?? .openai
            await readRun(on: hub, live: live)
        case .unsupported:
            log.log(.info, "\(config.name) has no runs, so replies to it stream as they did")
            providersWithoutRuns.insert(config.id)
            live.runID = nil
            await streamChat(request, on: hub, live: live)
        }
    }

    /// Reads the run's events after the reply's cursor, applying each frame
    /// whole and moving the cursor with it, then ends the reply as the run
    /// did, or walks away from the run when the reading stopped first. A
    /// frame that names images a tool made is applied once their bytes are
    /// kept (`keepImages`); one whose bytes were lost on the way is not, so
    /// the next reading meets it again. A look at a picture being drawn is
    /// shown and moves no cursor.
    func readRun(on hub: any RunProvider, live: LiveReply) async {
        guard let id = live.runID else { return }
        var end: RunEvent?
        var readAny = false
        for await event in hub.runEvents(id: id, after: live.cursor, frames: live.frames) {
            if case .preview(let frame) = event {
                live.work.show(frame)
                continue
            }
            guard case .frame(let seq, let events) = event else {
                end = event
                continue
            }
            // Never applied twice, whatever the hub sends.
            guard seq > live.cursor else { continue }
            guard await keepImages(named: events, from: hub) else { break }
            for chat in events { apply(chat, to: live) }
            live.cursor = seq
            readAny = true
        }
        switch end {
        case .ended(let info)? where info.status.isTerminal:
            endReply(live, as: info)
        case .notFound?:
            giveUp(live, saying: "no longer has the rest of this reply.", code: RunCode.notFound)
        case .refused(let error)?:
            log.log(.info, "a run was refused with \(error.code ?? "no code"), so it is given up")
            giveUp(live, saying: "would not send the rest of this reply. \(error.errorDescription ?? "")", error)
        default:
            guard !Task.isCancelled else { return await putDown(live, on: hub) }
            return walkAway(live, readAny: readAny)
        }
        readOnDetachedRuns()
    }

    /// Ends the reply as the run's last report says it ended. The report
    /// names the model the run was sent to, which a reply read on after the
    /// conversation's model was changed would otherwise get wrong.
    private func endReply(_ live: LiveReply, as info: RunInfo) {
        live.model = info.model ?? live.model
        switch info.status {
        case .completed:
            live.error = nil
            finish(live, finished: true, cancelled: false)
        case .failed:
            let reported = info.error.map { ProviderError.stream(code: $0.code, message: $0.message) }
            live.error = live.error ?? reported ?? .stream(code: nil, message: "the run failed")
            finish(live, finished: false, cancelled: false)
        case .cancelled, .queued, .inProgress:
            finish(live, finished: false, cancelled: true)
        }
    }

    /// The hub will not go on with the run: what arrived stays, with Continue,
    /// and a sentence, which starts with the machine's name, says why. An empty
    /// reply is not kept, and the question takes the sentence and Retry.
    func giveUp(_ live: LiveReply, saying why: String, code: String? = nil, _ error: ProviderError? = nil) {
        let name = conversations.first { $0.id == live.conversationID }.flatMap(provider(for:))?.name
        let failure = Failure(
            message: "\(name ?? "The machine") \(why)".trimmingCharacters(in: .whitespaces),
            code: error?.code ?? code, whereToLook: error?.whereToLook ?? .unknown)
        finish(live, finished: false, cancelled: false, refusal: failure)
    }

    /// The reply was put down. On the way to the background it walks away from
    /// the run; otherwise, Stop or a deletion, the run is cancelled on the hub
    /// and the reply ends as a stopped one. The cancel goes in a task of its
    /// own, since this one is cancelled and would call it off at once.
    private func putDown(_ live: LiveReply, on hub: any RunProvider) async {
        guard let id = live.runID, !live.detaching else {
            return finish(live, finished: false, cancelled: true, keepsRun: live.runID != nil)
        }
        let cancel = cancelRun(id, on: hub)
        finish(live, finished: false, cancelled: true)
        await cancel.value
    }

    /// Cancels a run on its hub, in a task of its own, and logs a failure by
    /// its code and nothing it named.
    @discardableResult
    func cancelRun(_ id: String, on hub: any RunProvider) -> Task<Void, Never> {
        Task { [log] in
            do throws(ProviderError) {
                _ = try await hub.cancelRun(id: id)
            } catch {
                log.log(.info, "a run could not be cancelled: \(error.code ?? "no code")")
            }
        }
    }
}
