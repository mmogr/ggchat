// DEBUG-only, for `MockEngine.swift`'s reason.
#if DEBUG
    import Foundation
    import Synchronization

    /// Stands in for gglib's model library beside ``MockEngine``, with the
    /// same behaviour: canned suggestions, search hits a page at a time and
    /// quantizations, each with a verdict as gglib would make it, the
    /// engine's one model installed (none for `no-models`, and too big for
    /// `too-big`), and a download that walks to done on a `Sleeper`.
    ///
    /// It keeps nothing: a download adds no model and a removal takes none
    /// away. The verdicts are fixed, whatever the reading says, because the
    /// app never computes one; the readings it is handed are kept in
    /// ``readings`` for a test to read back.
    public struct MockLibrary: ModelLibrary {
        public var behaviour: MockEngine.Behaviour
        public var sleeper: any Sleeper
        public var stepDelay: Duration
        /// Every reading a suggestion or a repository's quantizations were
        /// asked with, in order. A class, for `MockPairings`' reason: a test
        /// reads it back after handing the library to something that copied
        /// it.
        public let readings = MockReadings()

        public init(
            behaviour: MockEngine.Behaviour = .ready, sleeper: any Sleeper = ImmediateSleeper(),
            stepDelay: Duration = .milliseconds(400)
        ) {
            self.behaviour = behaviour
            self.sleeper = sleeper
            self.stepDelay = stepDelay
        }

        static let gigabyte: UInt64 = 1_073_741_824
        static let budget = 3 * gigabyte
        static let why = FitWhy(
            weightsBytes: gigabyte, kvBytesPerToken: 114_688, budgetBytes: budget, trainedCtx: 40_960)
        static let tooBig = FitVerdict.tooBig(needBytes: 5 * gigabyte, haveBytes: budget)

        public func suggested(reading: DeviceReading) async throws -> [Suggestion] {
            readings.keep(reading)
            return [
                Suggestion(
                    repo: Self.phoneRepo, quantization: "Q4_K_M", bytes: Self.gigabyte,
                    verdict: behaviour == .tooBig ? Self.tooBig : .fits(ctx: 16_384), why: Self.why,
                    rationale: "The largest of the suggested models this device runs at a useful context.")
            ]
        }

        /// The hits whose repository holds `query`, ignoring case, one to a
        /// page: the cursor is the index of the next hit.
        public func search(query: String, cursor: String?) async throws -> SearchPage {
            let hits = [
                SearchHit(
                    repo: Self.phoneRepo, likes: 120, downloads: 9_400, parametersB: 1.7, trainedCtx: 40_960),
                SearchHit(
                    repo: Self.deskRepo, likes: 880, downloads: 51_000, parametersB: 27, trainedCtx: 131_072),
            ]
            let wanted = query.trimmingCharacters(in: .whitespaces)
            let found = wanted.isEmpty ? hits : hits.filter { $0.repo.localizedCaseInsensitiveContains(wanted) }
            let start = cursor.flatMap(Int.init) ?? 0
            guard found.indices.contains(start) else { return SearchPage(hits: [], nextCursor: nil) }
            return SearchPage(
                hits: [found[start]], nextCursor: found.indices.contains(start + 1) ? String(start + 1) : nil)
        }

        static let phoneRepo = "mock/phone-1.7b-GGUF"
        static let deskRepo = "mock/desk-27b-GGUF"

        /// A quantization for each verdict there is, of the phone's
        /// repository; every one of any other is too big.
        public func quantizations(repo: String, reading: DeviceReading) async throws -> [QuantOffer] {
            readings.keep(reading)
            guard repo == Self.phoneRepo else {
                return [
                    QuantOffer(
                        name: "Q4_K_M", totalBytes: 16 * Self.gigabyte, shardCount: 1, verdict: Self.tooBig,
                        why: Self.why)
                ]
            }
            return [
                QuantOffer(
                    name: "Q4_K_M", totalBytes: Self.gigabyte, shardCount: 1,
                    verdict: behaviour == .tooBig ? Self.tooBig : .fits(ctx: 16_384), why: Self.why),
                QuantOffer(
                    name: "Q8_0", totalBytes: 2 * Self.gigabyte, shardCount: 1, verdict: .tight(ctx: 4_096),
                    why: Self.why),
                QuantOffer(
                    name: "F16", totalBytes: 4 * Self.gigabyte, shardCount: 2, verdict: Self.tooBig, why: Self.why),
                QuantOffer(
                    name: "IQ2_XS", totalBytes: Self.gigabyte / 2, shardCount: 1, verdict: .unknown(missing: .kvShape),
                    why: FitWhy(
                        weightsBytes: Self.gigabyte / 2, kvBytesPerToken: nil, budgetBytes: Self.budget, trainedCtx: nil
                    )),
            ]
        }

        public func installed() async throws -> [InstalledModel] {
            guard behaviour != .noModels else { return [] }
            return [
                InstalledModel(
                    id: 1, name: MockEngine.model.id, bytes: Self.gigabyte, trainedCtx: 40_960,
                    capabilities: MockEngine.model.capabilities ?? [],
                    verdict: behaviour == .tooBig ? Self.tooBig : .fits(ctx: 16_384))
            ]
        }

        /// Refuses an id that is not installed, as gglib does; removes
        /// nothing, since the mock keeps nothing.
        public func remove(id: Int64) async throws {
            guard try await installed().contains(where: { $0.id == id }) else { throw OnDeviceError.notFound }
        }

        /// Queued, four steps of running, verifying, done, one step apart.
        /// Ending the stream stops the walk.
        public func download(repo: String, quantization: String) async throws -> AsyncStream<DownloadProgress> {
            let id = "\(repo):\(quantization)"
            let total = Self.gigabyte
            let steps =
                [DownloadProgress(id: id, bytes: 0, total: total, state: .queued)]
                + (1...4).map { DownloadProgress(id: id, bytes: total / 4 * UInt64($0), total: total, state: .running) }
                + [.verifying, .done].map { DownloadProgress(id: id, bytes: total, total: total, state: $0) }
            let (stream, continuation) = AsyncStream.makeStream(of: DownloadProgress.self)
            let walk = Task { [sleeper, stepDelay] in
                for (index, step) in steps.enumerated() {
                    if index > 0, (try? await sleeper.sleep(for: stepDelay)) == nil { break }
                    continuation.yield(step)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in walk.cancel() }
            return stream
        }

        public func pauseAll() async {}

        public func resumeAll() async {}
    }

    /// The readings a ``MockLibrary`` was handed. DEBUG builds only.
    public final class MockReadings: Sendable {
        private let kept = Mutex<[DeviceReading]>([])

        public init() {}

        /// Every reading so far, in the order the library was asked.
        public var all: [DeviceReading] {
            kept.withLock { $0 }
        }

        fileprivate func keep(_ reading: DeviceReading) {
            kept.withLock { $0.append(reading) }
        }
    }
#endif
