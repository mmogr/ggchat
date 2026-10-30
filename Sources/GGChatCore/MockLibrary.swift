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
    /// What it installs is kept in its ``catalogue``, which the mock engine
    /// lists too, so a finished download joins the engine's models and a
    /// removal takes one away. The verdicts are fixed, whatever the reading
    /// says, because the app never computes one; the readings it is handed
    /// are kept in ``readings`` for a test to read back.
    public struct MockLibrary: ModelLibrary {
        public var behaviour: MockEngine.Behaviour
        public var sleeper: any Sleeper
        public var stepDelay: Duration
        /// Where a download keeps its partial file and its finished one, as
        /// gglib keeps them in the models directory; nil keeps nothing on
        /// disk.
        public var directory: URL?
        /// Every reading a suggestion or a repository's quantizations were
        /// asked with, in order. A class, for `MockPairings`' reason: a test
        /// reads it back after handing the library to something that copied
        /// it.
        public let readings = MockReadings()
        public let catalogue: Catalogue

        public init(
            behaviour: MockEngine.Behaviour = .ready, sleeper: any Sleeper = ImmediateSleeper(),
            stepDelay: Duration = .milliseconds(400), directory: URL? = nil, catalogue: Catalogue? = nil
        ) {
            self.behaviour = behaviour
            self.sleeper = sleeper
            self.stepDelay = stepDelay
            self.directory = directory
            self.catalogue = catalogue ?? Catalogue(behaviour: behaviour)
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

        public func quantizations(repo: String, reading: DeviceReading) async throws -> [QuantOffer] {
            readings.keep(reading)
            return offers(of: repo)
        }

        /// A quantization for each verdict there is, of the phone's
        /// repository; every one of any other is too big.
        func offers(of repo: String) -> [QuantOffer] {
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
                    name: "IQ2_XS", totalBytes: Self.gigabyte / 2, shardCount: 1,
                    verdict: .unknown(missing: .kvShape, cutOff: true),
                    why: FitWhy(
                        weightsBytes: Self.gigabyte / 2, kvBytesPerToken: nil, budgetBytes: Self.budget, trainedCtx: nil
                    )),
            ]
        }

        public func installed() async throws -> [InstalledModel] {
            catalogue.installed
        }

        /// Refuses an id that is not installed, as gglib does, and takes
        /// the model out of the catalogue and its file off the disk.
        public func remove(id: Int64) async throws {
            let name = catalogue.installed.first { $0.id == id }?.name
            guard let name, catalogue.remove(id: id) else { throw OnDeviceError.notFound }
            if let directory { try? FileManager.default.removeItem(at: Self.finishedFile(name, in: directory)) }
        }

        /// Queued, eight steps of running, verifying, done, one step apart,
        /// with the offer's size as the total; done installs it. See
        /// `DownloadWalk` for pausing and the files it keeps. Ending the
        /// stream stops the walk.
        public func download(repo: String, quantization: String) async throws -> AsyncStream<DownloadProgress> {
            let offer =
                offers(of: repo).first { $0.name == quantization }
                ?? QuantOffer(
                    name: quantization, totalBytes: Self.gigabyte, shardCount: 1, verdict: .fits(ctx: 16_384),
                    why: Self.why)
            let name = Self.installedName(repo: repo, quantization: quantization)
            let walk = DownloadWalk(
                id: "\(repo):\(quantization)", total: offer.totalBytes, sleeper: sleeper, stepDelay: stepDelay,
                catalogue: catalogue, partial: directory.map { Self.partialFile(name, in: $0) },
                finished: directory.map { Self.finishedFile(name, in: $0) })
            let (stream, continuation) = AsyncStream.makeStream(of: DownloadProgress.self)
            let walking = Task { [catalogue] in
                if await walk.run(saying: { continuation.yield($0) }) {
                    catalogue.install(offer, of: repo, as: name)
                    continuation.yield(walk.step(walk.total, .done))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in walking.cancel() }
            return stream
        }

        /// Every walk pauses at its next step and says so.
        public func pauseAll() async {
            catalogue.pause()
        }

        /// Every paused walk says it is running and goes on.
        public func resumeAll() async {
            catalogue.resume()
        }

        /// What the engine lists a downloaded quantization as:
        /// `mock-phone-1.7b-Q4_K_M` for `Q4_K_M` of `mock/phone-1.7b-GGUF`.
        public static func installedName(repo: String, quantization: String) -> String {
            let base = repo.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "-GGUF", with: "")
            return "\(base)-\(quantization)"
        }

        /// Where a download of `name` keeps what it has so far.
        public static func partialFile(_ name: String, in directory: URL) -> URL {
            directory.appending(path: "\(name).gguf.part")
        }

        /// Where a finished download of `name` is kept.
        public static func finishedFile(_ name: String, in directory: URL) -> URL {
            directory.appending(path: "\(name).gguf")
        }
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
