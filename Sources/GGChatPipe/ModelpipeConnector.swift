import Foundation
import GGChatCore
import Modelpipe

/// The real thing behind `PipeConnector`: a ticket in, a live pipe out.
///
/// The dial is a closure rather than a direct call to `mpConnect` so the
/// connector can be driven by a fake `MpPipeProtocol` in a test. Everything
/// this type does apart from the dial itself — validating before dialling,
/// dropping the token, turning the transport's errors into sentences — is
/// then testable without a network, a port or a far machine.
public struct ModelpipeConnector: PipeConnector {
    /// How a ticket becomes a pipe. Defaults to modelpipe's own `mpConnect`.
    public typealias Dial = @Sendable (String) async throws -> any MpPipeProtocol

    private let dial: Dial
    private let sleeper: any Sleeper
    private let grace: Duration

    public init(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200)
    ) {
        // Every field of `MpConnectOptions` is defaulted and the defaults are
        // the documented right answer. Spelled with its label because uniffi
        // emits the memberwise initialiser in Rust declaration order, so a
        // reordered record silently reorders the arguments here.
        self.init(sleeper: sleeper, grace: grace) { ticket in
            try await mpConnect(ticket: ticket, options: MpConnectOptions())
        }
    }

    init(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200),
        dial: @escaping Dial
    ) {
        self.sleeper = sleeper
        self.grace = grace
        self.dial = dial
    }

    /// Validates, dials, and hands back a session once the local port is
    /// bound — not once the far machine answers.
    ///
    /// The token is checked and then dropped. `mpConnect` takes no credential
    /// because modelpipe's connect side takes none: the listener forwards
    /// `Authorization` verbatim and the far edge is the only thing that checks
    /// it, so the token belongs to the HTTP client the app points at
    /// the session's `baseURL`. The check stays because `PipePairing` dials
    /// with the six-digit code *as* the token, and a pairing that silently
    /// accepted an empty one would spend a dial to learn nothing.
    ///
    /// The shape check stays for a second reason: `PipePairing` does none of
    /// its own, so this is the pairing path's only guard against a ticket
    /// that is not one.
    public func connect(ticket: String, token: String) async throws -> any PipeSession {
        if case .failure(let shape) = Ticket.validateShape(ticket) {
            throw PipeConnectError.invalidTicket(shape)
        }
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PipeConnectError.missingToken
        }
        do {
            return try ModelpipeSession(
                pipe: try await dial(ticket), sleeper: sleeper, grace: grace)
        } catch let error as MpError {
            throw Self.refusal(for: error)
        }
    }

    /// A transport error as something worth showing a person.
    ///
    /// `message()` and never `localizedDescription`: uniffi generates
    /// `errorDescription` for every error enum as `String(reflecting: self)`,
    /// so an `MpError` allowed to reach `AppModel.report` would put
    /// `modelpipe_ffi.MpError.Bind(reason: "Address already in use (os error
    /// 48)")` on screen and in the log. That compiles, reads as a plausible
    /// message in review, and only shows itself on a device.
    ///
    /// A bad ticket keeps its own case, because it is the one failure the
    /// person can fix by looking at what they pasted, and the form already
    /// says so in the app's own words.
    static func refusal(for error: MpError) -> PipeConnectError {
        switch error {
        case .BadTicket, .UnsupportedTicketVersion:
            return .dialFailed(message: error.message(), retryable: false)
        case .Bind, .Endpoint, .InvalidRelay, .PeerUnreachable, .Unknown:
            return .dialFailed(message: error.message(), retryable: error.isRetryable())
        }
    }
}
