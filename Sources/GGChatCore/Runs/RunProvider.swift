/// How a hub answered a request to start a run.
public enum RunStart: Sendable, Equatable {
    /// The run exists, new or already there under this id.
    case started(RunInfo)
    /// The hub has no runs: an older gglib, or another server. The request
    /// goes the old way, through `chat/completions`.
    case unsupported
}

/// What reading a run's events yields.
///
/// Every stream that is not cancelled ends with exactly one of `.ended`,
/// `.notFound`, `.refused` and `.dropped`, after any number of `.frame`s.
public enum RunEvent: Sendable, Equatable {
    /// One event of the run, numbered `seq`, and what it means for the reply.
    /// A frame is applied whole, and the cursor moves to its `seq` with it, so
    /// a reply is never left holding half of one.
    case frame(seq: UInt32, events: [ChatEvent])
    /// The run ended, and this is its last report.
    case ended(RunInfo)
    /// The hub does not have this run: it never did, it has dropped it, or it
    /// restarted and lost it.
    case notFound
    /// The hub, or whatever answered in its place, will not send the run: a
    /// 4xx other than `not_found`, or a report that cannot be read. Asking
    /// again would get the same answer.
    case refused(ProviderError)
    /// The stream stopped before the run ended: the hub could not be reached,
    /// answered 5xx, something else answered with a page that is not an event
    /// stream, or the connection dropped. The run may well go on; read
    /// again from the cursor once the hub can be reached.
    case dropped(ProviderError?)
}

/// A provider whose hub can own a reply, so the reply goes on without this
/// device and is read back from where it stopped. gglib's `runs` routes.
public protocol RunProvider: Provider {
    /// Starts the run `id` with the request `send` would stream. The id is
    /// this device's: 1 to 64 of `[A-Za-z0-9_-]`, a UUID string fitting.
    func startRun(id: String, _ request: ChatRequest) async throws(ProviderError) -> RunStart
    /// The events of the run `id` numbered above `after`, then its end.
    func runEvents(id: String, after: UInt32) -> AsyncStream<RunEvent>
    /// Stops the run `id`. Idempotent.
    func cancelRun(id: String) async throws(ProviderError) -> RunInfo
}

/// The codes a hub that has runs answers its runs routes with.
public enum RunCode {
    public static let notFound = "not_found"
    public static let tooManyRuns = "too_many_runs"
    public static let invalidRequest = "invalid_request"
    public static let conflict = "conflict"

    /// Every one of them. A 404 or 405 to a `PUT` carrying none of these is
    /// a hub with no runs route.
    public static let all: Set<String> = [notFound, tooManyRuns, invalidRequest, conflict]
}
