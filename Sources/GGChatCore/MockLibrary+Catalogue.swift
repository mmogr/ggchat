// DEBUG-only, for `MockEngine.swift`'s reason. Nested in `MockLibrary`, so
// `scripts/check_no_mock_in_release.sh` finds its symbols by that name.
#if DEBUG
    import Foundation
    import Synchronization

    extension MockLibrary {
        /// What the mock library has installed, which ``MockEngine`` lists as
        /// its models, and whether its downloads are paused: one holder the
        /// two share, as gglib's library and its engine share one catalogue,
        /// so a model the mock downloads joins the engine's list. A class,
        /// for `MockPairings`' reason. DEBUG builds only.
        public final class Catalogue: Sendable {
            /// One installed model, as the library lists it and as the
            /// engine's model list carries it.
            struct Entry: Sendable {
                var installed: InstalledModel
                var listed: ModelInfo
            }

            private struct State {
                var entries: [Entry]
                var nextID: Int64 = 2
                var paused = false
                var nextWaiter = 0
                var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
            }

            private let state: Mutex<State>

            /// The engine's one model installed, too big for `too-big`, and
            /// nothing for `no-models`.
            public init(behaviour: MockEngine.Behaviour = .ready) {
                let canned = Entry(
                    installed: InstalledModel(
                        id: 1, name: MockEngine.model.id, bytes: MockLibrary.gigabyte, trainedCtx: 40_960,
                        capabilities: MockEngine.model.capabilities ?? [],
                        verdict: behaviour == .tooBig ? MockLibrary.tooBig : .fits(ctx: 16_384)),
                    listed: MockEngine.model)
                state = Mutex(State(entries: behaviour == .noModels ? [] : [canned]))
            }

            /// What the library lists as installed, oldest first.
            public var installed: [InstalledModel] {
                state.withLock { $0.entries.map(\.installed) }
            }

            /// What the engine lists as its models, in the same order.
            public var listed: [ModelInfo] {
                state.withLock { $0.entries.map(\.listed) }
            }

            /// Installs `offer` of `repo` as `name`, in place of one already
            /// installed under that name.
            func install(_ offer: QuantOffer, of repo: String, as name: String) {
                state.withLock { state in
                    let id = state.entries.first { $0.installed.name == name }?.installed.id ?? state.nextID
                    if id == state.nextID { state.nextID += 1 }
                    state.entries.removeAll { $0.installed.name == name }
                    state.entries.append(
                        Entry(
                            installed: InstalledModel(
                                id: id, name: name, bytes: offer.totalBytes, trainedCtx: offer.why.trainedCtx,
                                capabilities: ["reasoning"], verdict: offer.verdict),
                            listed: ModelInfo(
                                id: name, ownedBy: "ggchat", description: "downloaded from \(repo)",
                                contextWindow: offer.why.trainedCtx.map { Int(clamping: $0) },
                                capabilities: ["reasoning"])))
                }
            }

            /// Removes the model with `id`, answering whether there was one.
            func remove(id: Int64) -> Bool {
                state.withLock { state in
                    let before = state.entries.count
                    state.entries.removeAll { $0.installed.id == id }
                    return state.entries.count < before
                }
            }

            var isPaused: Bool {
                state.withLock { $0.paused }
            }

            func pause() {
                state.withLock { $0.paused = true }
            }

            /// Lets every download waiting in ``waitWhilePaused()`` go on.
            func resume() {
                let waiting = state.withLock { state in
                    state.paused = false
                    defer { state.waiting = [:] }
                    return Array(state.waiting.values)
                }
                for waiter in waiting { waiter.resume() }
            }

            /// Returns once the downloads are not paused, or the caller is
            /// cancelled. Waits on a continuation, not a loop, so a paused
            /// download costs nothing while the app is away.
            func waitWhilePaused() async {
                let ticket = state.withLock { state in
                    defer { state.nextWaiter += 1 }
                    return state.nextWaiter
                }
                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        // Under the lock, so a cancellation that ran first is
                        // seen here rather than leaving this waiting for ever.
                        let now = state.withLock { state in
                            guard state.paused, !Task.isCancelled else { return true }
                            state.waiting[ticket] = continuation
                            return false
                        }
                        if now { continuation.resume() }
                    }
                } onCancel: {
                    state.withLock { $0.waiting.removeValue(forKey: ticket) }?.resume()
                }
            }
        }
    }
#endif
