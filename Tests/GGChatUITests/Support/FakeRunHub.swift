import GGChatCore
import Synchronization

/// A gglib hub with runs, in process: one reply, recorded as frames numbered
/// from 1, that every run it starts writes. Reads can be told to hold, as a
/// reply still being written does, or to drop once, as a connection does.
final class FakeRunHub: RunProvider {
    enum Start: Sendable {
        case runs
        /// A 404 or 405 with no run code: an older gglib.
        case unsupported
        case refused(ProviderError)
    }

    struct State {
        var start = Start.runs
        var frames: [[ChatEvent]]
        var ending = RunStatus.completed
        var error: RunError?
        /// The model the run's last report says it was sent to.
        var reportsModel: String?
        /// A read passes on frames up to this seq, then holds the stream
        /// open, as a run still being written does; nil ends it.
        var holdAt: UInt32?
        /// The next read passes on frames up to this seq, then drops.
        var dropAt: UInt32?
        /// Sends every frame whatever `after` asked for.
        var ignoresAfter = false
        /// Answers every read `not_found`.
        var forgotten = false
        /// Answers every read with this alone: a refusal, or a drop.
        var readAnswer: RunEvent?
        /// How many `PUT`s start the run and then lose their answer on the
        /// way back, as a transport error.
        var putsLost = 0
        /// Answers every cancel with a transport error.
        var cancelFails = false
        var starts: [(id: String, request: ChatRequest)] = []
        var reads: [(id: String, after: UInt32)] = []
        var cancels: [String] = []
        var chats: [ChatRequest] = []
        /// The reads holding their streams open, to end with `release()`.
        var held: [(id: String, continuation: AsyncStream<RunEvent>.Continuation)] = []
    }

    let state: Mutex<State>

    init(frames: [[ChatEvent]]) {
        state = Mutex(State(frames: frames))
    }

    /// The reply the frames add up to, as a run's reader applies them.
    static func frames(ofText text: String, reasoning: String) -> [[ChatEvent]] {
        MockProvider.tokens(of: reasoning).map { [.reasoning($0)] } + MockProvider.tokens(of: text).map { [.delta($0)] }
    }

    func with<T>(_ body: (inout State) -> T) -> T {
        state.withLock { body(&$0) }
    }

    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    /// The old way, for a hub that said it has no runs.
    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        with { $0.chats.append(request) }
        return AsyncStream { continuation in
            continuation.yield(.delta("the old way"))
            continuation.yield(.finished(reason: "stop", usage: nil))
            continuation.finish()
        }
    }

    func startRun(id: String, _ request: ChatRequest) async throws(ProviderError) -> RunStart {
        let (start, lost) = with { state in
            state.starts.append((id, request))
            state.putsLost -= 1
            return (state.start, state.putsLost >= 0)
        }
        if lost { throw .transport("the answer was lost") }
        switch start {
        case .runs: return .started(info(id, .queued, lastSeq: 0))
        case .unsupported: return .unsupported
        case .refused(let error): throw error
        }
    }

    func runEvents(id: String, after: UInt32) -> AsyncStream<RunEvent> {
        let (events, holds) = with { state -> ([RunEvent], Bool) in
            state.reads.append((id, after))
            if state.forgotten { return ([.notFound], false) }
            if let answer = state.readAnswer { return ([answer], false) }
            let limit = state.dropAt ?? state.holdAt ?? UInt32(state.frames.count)
            var events: [RunEvent] = []
            for (index, frame) in state.frames.enumerated() {
                let seq = UInt32(index + 1)
                guard seq <= limit, state.ignoresAfter || seq > after else { continue }
                events.append(.frame(seq: seq, events: frame))
            }
            if state.dropAt != nil {
                state.dropAt = nil
                return (events + [.dropped(.transport("the connection dropped"))], false)
            }
            // A cancelled run ends, as the hub ends one it has cancelled.
            if state.holdAt != nil, !state.cancels.contains(id) { return (events, true) }
            let status = state.cancels.contains(id) ? .cancelled : state.ending
            let end = info(id, status, lastSeq: limit, error: state.error, model: state.reportsModel)
            return (events + [.ended(end)], false)
        }
        return AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            if holds {
                with { $0.held.append((id, continuation)) }
            } else {
                continuation.finish()
            }
        }
    }

    /// Ends every held read with the rest of its frames and the run's end,
    /// and holds no more.
    func release() {
        let (held, frames, status, from, model) = with { state in
            defer {
                state.held = []
                state.holdAt = nil
            }
            return (state.held, state.frames, state.ending, state.holdAt ?? 0, state.reportsModel)
        }
        for (id, continuation) in held {
            for (index, frame) in frames.enumerated() where UInt32(index + 1) > from {
                continuation.yield(.frame(seq: UInt32(index + 1), events: frame))
            }
            continuation.yield(.ended(info(id, status, lastSeq: UInt32(frames.count), model: model)))
            continuation.finish()
        }
    }

    func cancelRun(id: String) async throws(ProviderError) -> RunInfo {
        let fails = with { state in
            state.cancels.append(id)
            return state.cancelFails
        }
        if fails { throw .transport("the hub could not be reached") }
        return info(id, .cancelled, lastSeq: 0)
    }

    private func info(
        _ id: String, _ status: RunStatus, lastSeq: UInt32, error: RunError? = nil, model: String? = nil
    ) -> RunInfo {
        RunInfo(
            id: id, kind: .chat, status: status, model: model, createdAtMs: 1_790_000_000_000, lastSeq: lastSeq,
            error: error)
    }
}
