import Foundation

/// The seam between the app and modelpipe. `MockPipeConnector` implements it
/// in DEBUG builds, and only there: the mock is compiled out of every other
/// configuration, so `UnavailablePipeConnector` is the only conformance a
/// shipped build contains. `ModelpipeConnector` will implement it when
/// `modelpipe-ffi` lands, and nothing above this protocol changes.
public protocol PipeConnector: Sendable {
    func connect(ticket: String, token: String) async throws -> any PipeSession
}

/// A live pipe. Requests go to `baseURL` through an ordinary
/// `OpenAICompatibleProvider`; there is no pipe-specific chat code.
///
/// The last three are what the pipe knows about itself, and they are
/// requirements rather than optional extras with defaults on purpose. A
/// default implementation here would be the protocol-level version of the
/// `default:` arm `PipeStatus+Modelpipe` argues against: a session that
/// forgot to answer ``closeReason`` would report a dead pipe as still open,
/// nothing would fail, and every decision made downstream of that answer
/// would quietly be made on a lie. Four conformances is a small price for
/// the compiler catching the fifth.
public protocol PipeSession: Sendable {
    /// `http://127.0.0.1:<port>/v1`
    var baseURL: URL { get }
    /// Current value first, then every change.
    var status: AsyncStream<PipeStatus> { get }
    /// Why this pipe closed, or `nil` while it is still open.
    ///
    /// Only meaningful once ``status`` has yielded `closed`; before that a
    /// session has nothing to explain and answers `nil`.
    var closeReason: PipeCloseReason? { get }
    /// The port and the relay counters, read at the moment of asking.
    var readings: PipeReadings { get }
    /// Tell the far endpoint that this device's network may have moved.
    ///
    /// Declared here rather than arriving with the code that calls it, so
    /// that the seam settles in one change instead of two. A session that
    /// cannot act on the news does nothing, which is the honest answer for a
    /// pipe that has no endpoint underneath it.
    func notifyNetworkChange() async
    func shutdown() async
}

/// Why a connect attempt failed.
///
/// The first three are refusals made here, before anything was dialled. The
/// last is the dial itself failing, which only a real connector can produce
/// and which the mock therefore never did — the seam described a world where
/// the only way to fail was to be wrong about the input.
public enum PipeConnectError: Error, Sendable, Equatable, LocalizedError {
    case invalidTicket(TicketShapeError)
    case missingToken
    /// Nothing in this build can dial a ticket. The ticket and the token were
    /// fine; the build has no `modelpipe-ffi` behind the seam, and the mock
    /// that stands in for it is DEBUG-only.
    case unavailable
    /// The dial was made and did not succeed: the port could not be bound,
    /// the endpoint could not start, the relay was not a URL, or the far
    /// machine could not be reached.
    ///
    /// The payload is `String` and `Bool` rather than the underlying error on
    /// purpose. This enum is `Equatable`, and tests compare its cases; an
    /// `any Error` payload would take both `Equatable` and `Sendable` away at
    /// once, and the compiler's complaint about the second reads like a
    /// complaint about the first.
    ///
    /// - Parameters:
    ///   - message: a sentence written to be read by a person. Never the
    ///     debug rendering of whatever the transport threw.
    ///   - retryable: whether dialling again could plausibly work. A bad
    ///     ticket is not retryable however many times it is pasted; a machine
    ///     that was asleep may answer next time.
    case dialFailed(message: String, retryable: Bool)

    public var errorDescription: String? {
        switch self {
        case .invalidTicket(let shape): shape.errorDescription
        case .missingToken: "A token is required alongside the ticket."
        case .unavailable: "This build cannot open a pipe yet; add the machine by its address instead."
        case .dialFailed(let message, _): message
        }
    }

    /// Whether offering the same dial again is worth the person's time.
    public var isRetryable: Bool {
        switch self {
        case .invalidTicket, .missingToken, .unavailable: false
        case .dialFailed(_, let retryable): retryable
        }
    }
}
