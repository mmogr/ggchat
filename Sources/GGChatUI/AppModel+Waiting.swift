import Foundation
import GGChatCore

/// A send through a pipe that is not connected, waiting until it is
/// (ADR 0006).
///
/// There is one at most, because a wait is the reply in flight and there is
/// one of those. It keeps no copy of the state it waits on: every change that
/// could end it wakes it, and it looks again. A status written, a dial ended
/// and a dial refused all wake it; Stop, the background and the provider's
/// removal cancel the reply, which ends it. There is no timer.
final class PipeWait {
    let providerID: UUID
    /// The sentence of a dial for this provider that was refused while this
    /// waited.
    var refusal: String?
    /// Whether this wait has dialled the pipe itself. It does so once at
    /// most, so a pipe that closes on its own afterwards is left to
    /// Reconnect or Stop rather than dialled again and again.
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

/// How a wait for a pipe ended.
enum PipeWaitEnd {
    /// The pipe is connected, and this is the provider to stream through.
    case connected(any Provider)
    /// A dial for it was refused, and this is the failure for the question.
    case refused(Failure)
    /// Stop, the background or the provider's removal called the reply off.
    case calledOff
}

extension AppModel {
    /// Waits until the pipe behind `config` is connected, direct or relayed.
    ///
    /// A dial already in flight for it — a resume, an opening, a reconnect or
    /// a pairing — is joined. A pipe that is installed and still looking is
    /// waited on. A pipe that is closed or was never dialled is dialled, once.
    func waitForPipe(_ config: ProviderConfig) async -> PipeWaitEnd {
        let wait = PipeWait(providerID: config.id)
        pipeWait = wait
        defer { if pipeWait === wait { pipeWait = nil } }
        if let end = look(at: wait) { return end }
        for await _ in wait.changes {
            if let end = look(at: wait) { return end }
        }
        return .calledOff
    }

    /// How the wait ends now, or nil while it goes on. Dials when nothing is
    /// dialling and no pipe is looking, if this wait has not dialled before.
    private func look(at wait: PipeWait) -> PipeWaitEnd? {
        let id = wait.providerID
        guard !Task.isCancelled, let config = providers.first(where: { $0.id == id }) else { return .calledOff }
        let connected = pipeStatuses[id]?.isConnected == true && pipeSessions[id] != nil
        if connected, let provider = makePipeProvider(for: config) {
            return .connected(provider)
        }
        if let refusal = wait.refusal {
            return .refused(Failure(message: refusal, code: nil, whereToLook: .unknown))
        }
        let looking = pipeSessions[id] != nil && pipeStatuses[id] != .closed
        guard !connecting.contains(id), !looking, !wait.dialled else { return nil }
        wait.dialled = true
        // Not a child of the reply: Stop ends the wait and leaves the dial
        // to finish, so the pipe is up for the next send.
        Task { await dial(config) }
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

    /// Gives a refused dial's sentence to the send waiting on this provider.
    /// Returns whether one took it: the question then shows the sentence, so
    /// nothing else should.
    @discardableResult
    func handToWaitingSend(_ sentence: String, for providerID: UUID) -> Bool {
        guard let wait = pipeWait, wait.providerID == providerID else { return false }
        wait.refusal = sentence
        wait.wake()
        return true
    }

    /// Asks the send waiting on this provider, if there is one, to look again.
    func wakeWaitingSend(for providerID: UUID) {
        guard let wait = pipeWait, wait.providerID == providerID else { return }
        wait.wake()
    }

    /// "Waiting for home · last heard 08:12", or "Waiting for home · not
    /// heard from yet", while this reply waits for its pipe; nil once it
    /// streams, and for every reply that never waited.
    public func waitingLine(for live: LiveReply, locale: Locale, calendar: Calendar) -> String? {
        guard let providerID = live.waitingFor, let config = providers.first(where: { $0.id == providerID }) else {
            return nil
        }
        return "Waiting for \(config.name) · \(lastHeardLine(for: providerID, locale: locale, calendar: calendar))"
    }
}
