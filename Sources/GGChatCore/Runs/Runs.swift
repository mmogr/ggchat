// The wire shapes of a run: a reply gglib owns from start to end, so it
// survives the app being locked or closed.
//
// Written by hand to mirror `gglib_core::domain::runs` in gglib. The bodies
// gglib records in `contracts/runs/recorded.json` are replayed against these
// types by `RunsWireTests`, so a change on either side shows there.
//
// An optional field decodes to `nil` whether the key is absent or `null`, and
// is left out when encoded, as gglib leaves it out.

/// What a run produces.
public enum RunKind: String, Codable, Sendable, Equatable {
    /// One chat completion.
    case chat
    /// An agent loop, which may call tools between completions.
    case agent
}

/// How the data of a run's numbered events is written.
public enum RunFrames: String, Codable, Sendable, Equatable {
    /// As the chat route's chunks, which a chat run records.
    case openai
    /// As gglib's agent events, which an agent run records, and a chat run
    /// started with gglib's own tools.
    case agent
    /// Some way this build does not know, from a later gglib. The run's
    /// report still reads, so its status and its end do; its events cannot
    /// be read, and a reply is not started on them.
    case unknown

    /// A word this build does not know reads as `.unknown`, so a report
    /// that carries one, and a list that holds such a report, still read.
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// Where a run is in its life.
public enum RunStatus: String, Codable, Sendable, Equatable {
    /// Accepted, and waiting for a model.
    case queued
    /// Producing events.
    case inProgress = "in_progress"
    /// Ended with a full reply.
    case completed
    /// Ended on an error, which the run's `error` names.
    case failed
    /// Ended because a client asked it to stop.
    case cancelled

    /// Whether the run has ended, so no further event will be logged.
    public var isTerminal: Bool {
        switch self {
        case .queued, .inProgress: false
        case .completed, .failed, .cancelled: true
        }
    }
}

/// Why a run failed.
public struct RunError: Codable, Sendable, Equatable {
    /// A stable, machine-readable code, such as `model_unavailable`.
    public let code: String
    /// A sentence for a person to read.
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// One run, as gglib reports it.
public struct RunInfo: Codable, Sendable, Equatable, Identifiable {
    /// The run's id, minted by the client that started it.
    public let id: String
    /// What the run produces.
    public let kind: RunKind
    /// Where the run is in its life.
    public let status: RunStatus
    /// The model the run was sent to, when one was named.
    public let model: String?
    /// The paired device that started the run; `nil` when it came from the
    /// machine gglib runs on.
    public let device: String?
    /// When the run was accepted, in milliseconds since the Unix epoch.
    public let createdAtMs: UInt64
    /// When the run ended, in milliseconds since the Unix epoch; `nil` while
    /// it has not.
    public let finishedAtMs: UInt64?
    /// The number of the last event logged for the run; 0 when none has been.
    public let lastSeq: UInt32
    /// Why the run failed; set only when `status` is `.failed`.
    public let error: RunError?
    /// How the run's events are written, so a reader picks the decoder for
    /// them. Absent from a run that records the chat route's chunks, and
    /// from every gglib before a chat run could carry tools: nil reads as
    /// `.openai`.
    public let frames: RunFrames?

    public init(
        id: String, kind: RunKind, status: RunStatus, model: String? = nil, device: String? = nil,
        createdAtMs: UInt64, finishedAtMs: UInt64? = nil, lastSeq: UInt32, error: RunError? = nil,
        frames: RunFrames? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.model = model
        self.device = device
        self.createdAtMs = createdAtMs
        self.finishedAtMs = finishedAtMs
        self.lastSeq = lastSeq
        self.error = error
        self.frames = frames
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case status
        case model
        case device
        case createdAtMs = "created_at_ms"
        case finishedAtMs = "finished_at_ms"
        case lastSeq = "last_seq"
        case error
        case frames
    }
}

/// A set of runs, as a listing returns them.
public struct RunList: Codable, Sendable, Equatable {
    /// The runs, in the order the listing chose.
    public let runs: [RunInfo]

    public init(runs: [RunInfo]) {
        self.runs = runs
    }
}
