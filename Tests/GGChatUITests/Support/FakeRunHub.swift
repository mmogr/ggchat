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
        /// A read passes on frames up to this seq, then holds the stream
        /// open, as a run still being written does; nil ends it.
        var holdAt: UInt32?
        /// The next read passes on frames up to this seq, then drops.
        var dropAt: UInt32?
        /// Sends every frame whatever `after` asked for.
        var ignoresAfter = false
        /// Answers every read `not_found`.
        var forgotten = false
        var starts: [(id: String, request: ChatRequest)] = []
        var reads: [(id: String, after: UInt32)] = []
        var cancels: [String] = []
        var chats: [ChatRequest] = []
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
        let start = with { state in
            state.starts.append((id, request))
            return state.start
        }
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
            if state.holdAt != nil { return (events, true) }
            let status = state.cancels.contains(id) ? .cancelled : state.ending
            return (events + [.ended(info(id, status, lastSeq: limit, error: state.error))], false)
        }
        return AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            if !holds { continuation.finish() }
        }
    }

    func cancelRun(id: String) async throws(ProviderError) -> RunInfo {
        with { $0.cancels.append(id) }
        return info(id, .cancelled, lastSeq: 0)
    }

    private func info(_ id: String, _ status: RunStatus, lastSeq: UInt32, error: RunError? = nil) -> RunInfo {
        RunInfo(id: id, kind: .chat, status: status, createdAtMs: 1_790_000_000_000, lastSeq: lastSeq, error: error)
    }
}
