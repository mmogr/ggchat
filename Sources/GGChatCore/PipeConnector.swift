import Foundation

/// The seam between the app and modelpipe. `PipeConnectorFactory` returns
/// `ModelpipeConnector`, from `GGChatPipe`, in every build but DEBUG, and
/// `MockPipeConnector` in DEBUG, the only configuration the mock is compiled
/// into. `UnavailablePipeConnector` is still compiled and refuses every
/// ticket, but nothing in the app returns it; it is the sentinel the release
/// check looks for.
public protocol PipeConnector: Sendable {
    func connect(ticket: String, token: String) async throws -> any PipeSession
    /// Trade the one-time code in a pairing string for a key of this
    /// device's own, over a pipe this leaves up.
    ///
    /// A requirement rather than a defaulted extension, for ``PipeSession``'s
    /// reason below: a connector that forgot to pair would refuse every first
    /// pairing at run time instead of failing to compile.
    ///
    /// The whole pairing string goes in — `ticket-code`, in either ASCII case
    /// — because the far machine's pairing route is reachable only *through*
    /// the pipe the ticket dials, so the two halves are one argument to
    /// whatever does the dialling.
    ///
    /// - Parameters:
    ///   - pairing: the string `gglib remote invite` printed, with its code.
    ///   - deviceName: what the far machine should list this device as, or
    ///     `nil` to send none. Not the provider's name, which is what this
    ///     side calls the far machine.
    func pair(pairing: String, deviceName: String?) async throws -> PairedPipe
}

/// What a first pairing produces: this device's key, the name the far
/// machine holds it under, and the pipe the code was redeemed over.
///
/// The pipe comes back still up, and it becomes the provider's first
/// session. Hanging it up and dialling again would cost a second hole punch
/// and a second endpoint identity, so the fingerprint the far machine
/// recorded at redemption would never be the one this device then chats
/// from.
public struct PairedPipe: Sendable {
    /// The pipe the code was redeemed over, still up.
    ///
    /// `nil` when the pairing succeeded but the pipe it came up on is not one
    /// this app will send a request to. The code is spent by then and the key
    /// is real, so it is handed back to be stored and the pipe is hung up
    /// rather than kept; the provider is left to be dialled again.
    public let session: (any PipeSession)?
    /// This device's key from now on. Named `token` and not `key` so that
    /// `scripts/check_log_calls.sh`, which refuses a log line interpolating
    /// `token`, catches one that carries this.
    public let token: String
    /// The name the far machine holds the key under, as it recorded it.
    public let device: String

    public init(session: (any PipeSession)?, token: String, device: String) {
        self.session = session
        self.token = token
        self.device = device
    }
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
    /// Tell this device's endpoint that the network under it may have moved.
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
    /// The far machine would not take that code.
    ///
    /// A case of its own rather than one more `dialFailed`, because it is the
    /// one refusal with somewhere to send the person: the code may be wrong,
    /// expired or already spent, and the next attempt starts on the other
    /// machine. The payload is the sentence whoever refused it wrote, and the
    /// line naming what to run there is added here.
    case pairingRefused(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidTicket(let shape): shape.errorDescription
        case .missingToken: "A token is required alongside the ticket."
        case .unavailable: "This build cannot open a pipe yet; add the machine by its address instead."
        case .dialFailed(let message, _): message
        case .pairingRefused(let message):
            message + " Run `gglib remote invite` there again."
        }
    }

    /// Whether offering the same dial again is worth the person's time.
    public var isRetryable: Bool {
        switch self {
        case .invalidTicket, .missingToken, .unavailable, .pairingRefused: false
        case .dialFailed(_, let retryable): retryable
        }
    }
}
