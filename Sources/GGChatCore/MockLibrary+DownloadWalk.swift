// DEBUG-only, for `MockEngine.swift`'s reason. Nested in `MockLibrary`, so
// `scripts/check_no_mock_in_release.sh` finds its symbols by that name.
#if DEBUG
    import Foundation

    extension MockLibrary {
        /// One mock download's steps, one `stepDelay` apart on the sleeper:
        /// queued, eight of running with the bytes going up to the total,
        /// then verifying. Paused, it finishes the step it is on, says paused
        /// at those bytes and waits; resumed, it says running at the same
        /// bytes and goes on, so the bytes never go back.
        ///
        /// With files named, it keeps a partial that grows a byte a step, as
        /// gglib keeps a `.part`, makes it the finished file once verified,
        /// and deletes it when the walk is called off.
        struct DownloadWalk: Sendable {
            let id: String
            let total: UInt64
            let sleeper: any Sleeper
            let stepDelay: Duration
            let catalogue: Catalogue
            let partial: URL?
            let finished: URL?

            static let runningSteps: UInt64 = 8

            func step(_ bytes: UInt64, _ state: DownloadState) -> DownloadProgress {
                DownloadProgress(id: id, bytes: bytes, total: total, state: state)
            }

            /// Says each step up to verifying, and answers whether the walk
            /// got through it: false once it is called off, with the partial
            /// deleted.
            func run(saying say: (DownloadProgress) -> Void) async -> Bool {
                say(step(0, .queued))
                start()
                var bytes: UInt64 = 0
                for index in 1...Self.runningSteps {
                    if catalogue.isPaused {
                        say(step(bytes, .paused))
                        await catalogue.waitWhilePaused()
                        guard !Task.isCancelled else { return discard() }
                        say(step(bytes, .running))
                    }
                    guard await waited() else { return discard() }
                    bytes = total * index / Self.runningSteps
                    grow()
                    say(step(bytes, .running))
                }
                guard await waited() else { return discard() }
                say(step(total, .verifying))
                guard await waited() else { return discard() }
                finish()
                return true
            }

            private func waited() async -> Bool {
                (try? await sleeper.sleep(for: stepDelay)) != nil
            }

            private func start() {
                guard let partial else { return }
                FileManager.default.createFile(atPath: partial.path(percentEncoded: false), contents: nil)
            }

            private func grow() {
                guard let partial, let handle = try? FileHandle(forWritingTo: partial) else { return }
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data([0]))
            }

            /// Deletes the partial, and answers false for `run` to return.
            private func discard() -> Bool {
                if let partial { try? FileManager.default.removeItem(at: partial) }
                return false
            }

            private func finish() {
                guard let partial, let finished else { return }
                try? FileManager.default.removeItem(at: finished)
                try? FileManager.default.moveItem(at: partial, to: finished)
            }
        }
    }
#endif
