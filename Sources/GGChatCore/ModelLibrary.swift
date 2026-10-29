/// The models this device can run: what suits it, what Hugging Face has,
/// which quantizations of a repository fit, what is installed, and the
/// downloads in flight. Mirrors gglib-ffi's `Library`, call for call;
/// `EngineFactory` chooses the one behind it.
///
/// This app never computes a fit. Every ``FitVerdict`` arrives as a value,
/// made by gglib from a ``DeviceReading`` the app passes in.
public protocol ModelLibrary: Sendable {
    /// The models gglib suggests for a device with this reading, best first.
    func suggested(reading: DeviceReading) async throws -> [Suggestion]
    /// A page of Hugging Face's answer to `query`, from `cursor` or the start.
    func search(query: String, cursor: String?) async throws -> SearchPage
    /// Each quantization `repo` publishes, with how it fits this reading.
    func quantizations(repo: String, reading: DeviceReading) async throws -> [QuantOffer]
    /// The models already on this device.
    func installed() async throws -> [InstalledModel]
    /// Deletes an installed model's files and its row.
    func remove(id: Int64) async throws
    /// Downloads one quantization of `repo`. The stream yields its progress,
    /// current first, and ends after `done` or `failed`; ending it before
    /// that cancels the download. ``pauseAll()`` yields `paused` in it and
    /// leaves it open, and ``resumeAll()`` goes on in the same stream.
    func download(repo: String, quantization: String) async throws -> AsyncStream<DownloadProgress>
    /// Pauses every download in flight, as the app leaves the foreground.
    func pauseAll() async
    /// Resumes what ``pauseAll()`` paused.
    func resumeAll() async
}

/// Whether a model fits this device, as gglib judged it, mirroring
/// gglib-ffi's `FitVerdict`.
public enum FitVerdict: Sendable, Equatable, Hashable {
    /// A context above the smallest fits; `ctx` is the largest that does.
    case fits(ctx: UInt64)
    /// Only the smallest context fits; `ctx` is that size.
    case tight(ctx: UInt64)
    /// Not even the smallest context fits: the model needs a budget of
    /// `needBytes` and the device gives `haveBytes`.
    case tooBig(needBytes: UInt64, haveBytes: UInt64)
    /// gglib could not tell without `missing`.
    case unknown(missing: MissingInput)
}

/// What a ``FitVerdict/unknown(missing:)`` could not do without.
public enum MissingInput: Sendable, Equatable, Hashable {
    /// The model's trained context.
    case trainedContext
    /// The model's KV shape: layers, KV heads and head dimensions.
    case kvShape
    /// The size of the weights.
    case weights
    /// The memory budget, from a reading of the device.
    case budget
}

/// The numbers a ``FitVerdict`` was reached from, for the sheet that says
/// why, mirroring gglib-ffi's `FitWhy`. Absent is unknown, never zero.
public struct FitWhy: Sendable, Equatable, Hashable {
    public var weightsBytes: UInt64?
    public var kvBytesPerToken: UInt64?
    public var budgetBytes: UInt64?
    public var trainedCtx: UInt64?

    public init(weightsBytes: UInt64?, kvBytesPerToken: UInt64?, budgetBytes: UInt64?, trainedCtx: UInt64?) {
        self.weightsBytes = weightsBytes
        self.kvBytesPerToken = kvBytesPerToken
        self.budgetBytes = budgetBytes
        self.trainedCtx = trainedCtx
    }
}

/// A model gglib suggests for this device, mirroring gglib-ffi's
/// `Suggestion`.
public struct Suggestion: Sendable, Equatable, Hashable {
    public var repo: String
    public var quantization: String
    public var bytes: UInt64
    public var verdict: FitVerdict
    public var why: FitWhy
    /// gglib's sentence on why this one.
    public var rationale: String

    public init(
        repo: String, quantization: String, bytes: UInt64, verdict: FitVerdict, why: FitWhy, rationale: String
    ) {
        self.repo = repo
        self.quantization = quantization
        self.bytes = bytes
        self.verdict = verdict
        self.why = why
        self.rationale = rationale
    }
}

/// One repository in a search, mirroring gglib-ffi's `SearchHit`.
public struct SearchHit: Sendable, Equatable, Hashable {
    public var repo: String
    public var likes: UInt64
    public var downloads: UInt64
    /// Billions of parameters, when the repository says.
    public var parametersB: Double?
    public var trainedCtx: UInt64?

    public init(repo: String, likes: UInt64, downloads: UInt64, parametersB: Double?, trainedCtx: UInt64?) {
        self.repo = repo
        self.likes = likes
        self.downloads = downloads
        self.parametersB = parametersB
        self.trainedCtx = trainedCtx
    }
}

/// A page of a search, mirroring gglib-ffi's `SearchPage`.
public struct SearchPage: Sendable, Equatable, Hashable {
    public var hits: [SearchHit]
    /// Where the next page starts, or nil on the last.
    public var nextCursor: String?

    public init(hits: [SearchHit], nextCursor: String?) {
        self.hits = hits
        self.nextCursor = nextCursor
    }
}

/// One quantization a repository publishes, mirroring gglib-ffi's
/// `QuantOffer`.
public struct QuantOffer: Sendable, Equatable, Hashable {
    /// `Q4_K_M`, `Q8_0` and so on.
    public var name: String
    public var totalBytes: UInt64
    public var shardCount: UInt32
    public var verdict: FitVerdict
    public var why: FitWhy

    public init(name: String, totalBytes: UInt64, shardCount: UInt32, verdict: FitVerdict, why: FitWhy) {
        self.name = name
        self.totalBytes = totalBytes
        self.shardCount = shardCount
        self.verdict = verdict
        self.why = why
    }
}

/// A model on this device, mirroring gglib-ffi's `InstalledModel`. `name`
/// is what the engine's model list calls it.
public struct InstalledModel: Sendable, Equatable, Hashable, Identifiable {
    public var id: Int64
    public var name: String
    public var bytes: UInt64
    public var trainedCtx: UInt64?
    /// gglib's words for what it can do beyond chat, as the model list
    /// carries them.
    public var capabilities: [String]
    public var verdict: FitVerdict

    public init(
        id: Int64, name: String, bytes: UInt64, trainedCtx: UInt64?, capabilities: [String], verdict: FitVerdict
    ) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.trainedCtx = trainedCtx
        self.capabilities = capabilities
        self.verdict = verdict
    }
}

/// How far a download has got, mirroring gglib-ffi's `DownloadProgress`.
public struct DownloadProgress: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var bytes: UInt64
    /// Unknown until the server says.
    public var total: UInt64?
    public var state: DownloadState

    public init(id: String, bytes: UInt64, total: UInt64?, state: DownloadState) {
        self.id = id
        self.bytes = bytes
        self.total = total
        self.state = state
    }
}

/// Where a download is, mirroring gglib-ffi's download states.
public enum DownloadState: Sendable, Equatable, Hashable {
    case queued
    case running
    case paused
    case verifying
    case done
    case failed(reason: String)
}
