import Foundation
import GGChatCore

/// A send through a session that is not up, waiting until it is (ADR 0006):
/// a pipe that is not connected, or this device's engine while it is not
/// serving (ADR 0015).
///
/// There is one at most per conversation, because a wait is that
/// conversation's reply in flight. It keeps no copy of the state it waits on: every change that
/// could end it wakes it, and it looks again. A status written, a dial ended,
/// a dial refused, a serve refused and a serve ended, landed or not, all
/// wake it; Stop, the background and the provider's removal cancel the
/// reply, which ends it. There is no timer.
final class SessionWait {
    let providerID: UUID
    /// The sentence of a dial or a serve for this provider that was refused
    /// while this waited.
    var refusal: String?
    /// Whether this wait has dialled the pipe, or served the engine, itself.
    /// It does so once at most, so a session that ends on its own afterwards
    /// is left to Reconnect or Stop rather than started again and again; and
    /// never while another wait's dial for the same pipe is out
    /// (`waitDials`), or a serve is under way.
    var dialled = false
    let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(providerID: UUID) {
        self.providerID = providerID
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.changes = changes
        self.continuation = continuation
    }

    func wake() {
        continuation.yield()
    }
}

/// How a wait for a session ended.
enum SessionWaitEnd {
    /// The session is up, and this is the provider to stream through.
    case connected(any Provider)
    /// A dial or a serve for it was refused, and this is the failure for the
    /// question.
    case refused(Failure)
    /// Stop, the background or the provider's removal called the reply off.
    case calledOff
}

extension AppModel {
    /// Whether a send through `config` waits for its session rather than
    /// going now: a pipe that is not connected, or this device's engine
    /// while it is not serving. A server by address never waits, and nor
    /// does an engine this build lacks, whose send is refused with a sentence
    /// about the build.
    func waitsForSession(_ config: ProviderConfig) -> Bool {
        switch config.kind {
        case .openAICompatible: false
        case .pipe: pipeStatuses[config.id]?.isConnected != true
        case .onDevice: engine.isAvailable && !sessionIsUp(config)
        }
    }

    /// Waits until the session behind `config` is up: its pipe connected,
    /// direct or relayed, or this device's engine serving.
    ///
    /// A dial already in flight for a pipe — a resume, an opening, a
    /// reconnect or a pairing — is joined. A pipe that is installed and still
    /// looking is waited on. A pipe that is closed or was never dialled is
    /// dialled, once. The engine is served the same way: a serve in flight
    /// is joined, and otherwise one is started, once.
    func waitForSession(_ config: ProviderConfig, for conversationID: UUID) async -> SessionWaitEnd {
        let wait = SessionWait(providerID: config.id)
        sessionWaits[conversationID] = wait
        defer { if sessionWaits[conversationID] === wait { sessionWaits[conversationID] = nil } }
        if let end = look(at: wait) { return end }
        for await _ in wait.changes {
            if let end = look(at: wait) { return end }
        }
        return .calledOff
    }

    /// How the wait ends now, or nil while it goes on. Dials when nothing is
    /// dialling and no pipe is looking, if this wait has not dialled before.
    private func look(at wait: SessionWait) -> SessionWaitEnd? {
        let id = wait.providerID
        guard !Task.isCancelled, let config = providers.first(where: { $0.id == id }) else { return .calledOff }
        if config.kind == .onDevice { return lookAtEngine(for: wait, config) }
        let connected = pipeStatuses[id]?.isConnected == true && pipeSessions[id] != nil
        if connected, let provider = makePipeProvider(for: config) {
            return .connected(provider)
        }
        if let refusal = wait.refusal {
            return .refused(Failure(message: refusal, code: nil, whereToLook: .unknown))
        }
        let looking = pipeSessions[id] != nil && pipeStatuses[id] != .closed
        guard !connecting.contains(id), !waitDials.contains(id), !looking, !wait.dialled else { return nil }
        wait.dialled = true
        // Marked until the dial ends. A dial for a closed pipe hangs it up
        // first, which takes a while, and a second wait looking then would
        // hang it up again and call this dial off.
        waitDials.insert(id)
        // Not a child of the reply: Stop ends the wait and leaves the dial
        // to finish, so the pipe is up for the next send.
        Task {
            await dial(config)
            waitDials.remove(id)
        }
        return nil
    }

    /// How a wait for this device's engine ends now, or nil while it goes
    /// on. Serves the engine when no serve is under way, if this wait has not
    /// served it before; a shutdown in flight is waited out by `serveEngine`
    /// itself. Every serve's end wakes every wait on the engine, so a wait
    /// that joined a serve put down for landing late serves afresh.
    private func lookAtEngine(for wait: SessionWait, _ config: ProviderConfig) -> SessionWaitEnd? {
        if sessionIsUp(config), let provider = makeEngineProvider(for: config) {
            return .connected(provider)
        }
        if let refusal = wait.refusal {
            return .refused(Failure(message: refusal, code: nil, whereToLook: .unknown))
        }
        guard engineServing == nil, !wait.dialled else { return nil }
        wait.dialled = true
        // Not a child of the reply, for the dial's reason below.
        Task {
            await serveEngine()
            wakeWaitingSend(for: config.id)
        }
        return nil
    }

    /// A waiting send's own dial. A closed pipe still installed is hung up
    /// first, as Reconnect does, because a dial refuses a provider that holds
    /// a session. Quiet, because a waiting send takes the refusal onto its
    /// question, and one that has been stopped has nobody left to tell.
    private func dial(_ config: ProviderConfig) async {
        if pipeSessions[config.id] != nil { await disconnectPipe(for: config.id) }
        await connectPipe(for: config, quietly: true)
    }

    /// Gives a refused dial's or serve's sentence to every send waiting on
    /// this provider. Returns whether one took it: the questions then show
    /// the sentence, so nothing else should.
    @discardableResult
    func handToWaitingSend(_ sentence: String, for providerID: UUID) -> Bool {
        let waits = sessionWaits.values.filter { $0.providerID == providerID }
        for wait in waits {
            wait.refusal = sentence
            wait.wake()
        }
        return !waits.isEmpty
    }

    /// Asks every send waiting on this provider to look again.
    func wakeWaitingSend(for providerID: UUID) {
        for wait in sessionWaits.values where wait.providerID == providerID { wait.wake() }
    }

    /// "Waiting for home · last heard 08:12", or "Waiting for home · not
    /// heard from yet", while this reply waits for its pipe, and "Waiting
    /// for This iPhone to start its engine" while it waits for the engine;
    /// nil once it streams, and for every reply that never waited.
    public func waitingLine(for live: LiveReply, locale: Locale, calendar: Calendar) -> String? {
        guard let providerID = live.waitingFor, let config = providers.first(where: { $0.id == providerID }) else {
            return nil
        }
        if config.kind == .onDevice { return "Waiting for \(config.name) to start its engine" }
        return "Waiting for \(config.name) · \(lastHeardLine(for: providerID, locale: locale, calendar: calendar))"
    }
}
