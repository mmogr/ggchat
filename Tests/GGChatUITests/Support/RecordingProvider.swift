import GGChatCore
import Synchronization

/// Keeps every request it is asked to stream and hands each one on to the
/// provider it wraps, so a test can read what the app sent as well as what
/// came back.
///
/// The app builds a provider afresh for every request, from whatever the
/// registry holds at its base URL, so a test that needs the next reply to go
/// differently swaps the wrapped provider with ``wrap(_:)`` rather than
/// registering a new one: the requests seen so far stay here, and the next
/// one is kept with them.
final class RecordingProvider: Provider {
    private struct State {
        var inner: any Provider
        var requests: [ChatRequest] = []
    }

    private let state: Mutex<State>

    init(wrapping inner: any Provider) {
        state = Mutex(State(inner: inner))
    }

    /// Every request streamed so far, in the order they went out.
    var requests: [ChatRequest] {
        state.withLock { $0.requests }
    }

    /// Hands every request from now on to `inner` instead.
    func wrap(_ inner: any Provider) {
        state.withLock { $0.inner = inner }
    }

    func models() async throws -> [ModelInfo] {
        let inner = state.withLock { $0.inner }
        return try await inner.models()
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        let inner = state.withLock { state -> any Provider in
            state.requests.append(request)
            return state.inner
        }
        return inner.stream(request)
    }
}
