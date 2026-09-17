import Foundation
import GGChatCore
import Modelpipe

/// The real thing behind `PipeConnector`: a ticket in, a live pipe out, and
/// a pairing string in, a key and the pipe it was redeemed over out.
///
/// The dial and the pairing are closures rather than direct calls to
/// `mpConnect` and `mpPair` so the connector can be driven by a fake
/// `MpPipeProtocol` in a test. Everything this type does apart from those two
/// calls — validating before dialling, dropping the token, keeping the paired
/// pipe, turning the binding's errors into sentences — is then testable
/// without a network, a port or a far machine.
public struct ModelpipeConnector: PipeConnector {
    /// How a ticket becomes a pipe. Defaults to modelpipe's own `mpConnect`.
    public typealias Dial = @Sendable (String) async throws -> any MpPipeProtocol

    /// What `mpPair` hands back, in the three fields this app uses.
    ///
    /// A type of its own rather than `MpPaired`, because no test can build
    /// one of those: its `pipe` is the concrete `MpPipe`, and an
    /// `MpPipe(noHandle:)` crashes the moment anything asks it for a base
    /// URL. `any MpPipeProtocol` is what a fake can be.
    public struct Paired: Sendable {
        /// The pipe the code was redeemed over, still up.
        public var pipe: any MpPipeProtocol
        /// This device's key from now on.
        public var apiKey: String
        /// The name the far machine holds the key under.
        public var device: String

        public init(pipe: any MpPipeProtocol, apiKey: String, device: String) {
            self.pipe = pipe
            self.apiKey = apiKey
            self.device = device
        }
    }

    /// How a pairing string becomes a key and the pipe it was redeemed over.
    /// Defaults to modelpipe's own `mpPair`.
    public typealias Pair = @Sendable (String, String?) async throws -> Paired

    /// How long the far machine has to answer the dial the code is redeemed
    /// over. Thirty seconds because that is roughly what iroh spends failing
    /// to reach a machine that is switched off, and it is what gglib's own
    /// connect side waits. modelpipe adds its own fixed deadline for the
    /// redeem itself once the pipe is up.
    public static let reachWithinMs: UInt64 = 30_000

    /// Who reads a ticket before it is dialled. Stateless — no stored
    /// properties, one C call — so one of these is shared rather than made
    /// per dial, and it is not injectable: a fake here would only prove that
    /// a test's own parser agrees with the test.
    static let reader = ModelpipePairingReader()

    private let dial: Dial
    private let pairing: Pair
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
        } pairing: { pairing, label in
            let paired = try await mpPair(
                pairing: pairing, label: label, options: MpConnectOptions(),
                reachWithinMs: Self.reachWithinMs)
            return Paired(pipe: paired.pipe, apiKey: paired.apiKey, device: paired.device)
        }
    }

    init(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200),
        dial: @escaping Dial,
        pairing: @escaping Pair = { _, _ in
            throw PipeConnectError.unavailable
        }
    ) {
        self.sleeper = sleeper
        self.grace = grace
        self.dial = dial
        self.pairing = pairing
    }

    /// Validates, dials, and hands back a session once the local port is
    /// bound — not once the far machine answers.
    ///
    /// modelpipe reads the ticket before anything is dialled, through the
    /// very ``ModelpipePairingReader`` the form reads what is typed with — not
    /// a second call to `mpReadPairing` beside it. A refused read has to
    /// become a sentence somehow, and that mapping, including what to say when
    /// the binding throws something that is not an `MpPairError` at all, is
    /// the reader's and is written once. A commit that deletes a parse written
    /// twice should not leave its error mapping written twice one module down.
    ///
    /// It is a decode and not a look at the shape, so a ticket whose checksum
    /// is wrong costs no dial either. A string that carries a code is refused
    /// here as well: a code is redeemed, not dialled, and
    /// ``pair(pairing:deviceName:)`` is the way in for one.
    ///
    /// The token is checked and then dropped. `mpConnect` takes no credential
    /// because modelpipe's connect side takes none: the listener forwards
    /// `Authorization` verbatim and the far edge is the only thing that checks
    /// it, so the token belongs to the HTTP client the app points at
    /// the session's `baseURL`. The check stays for the other way in: a bare
    /// ticket, added by a device that already holds its key, where an empty
    /// token means every request through the pipe would be refused at the far
    /// edge after a dial spent finding that out.
    public func connect(ticket: String, token: String) async throws -> any PipeSession {
        let read: ReadPairing
        switch Self.reader.read(ticket) {
        case .success(let value):
            read = value
        case .failure(.malformed(let message)):
            throw PipeConnectError.invalidTicket(message: message)
        }
        guard !read.hasCode else {
            throw PipeConnectError.invalidTicket(
                message: "That string carries a pairing code. A code is redeemed once, not dialled; "
                    + "add the machine with it instead of storing it as a ticket.")
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

    /// Trades the code in a pairing string for this device's key, and keeps
    /// the pipe it was redeemed over.
    ///
    /// The whole string goes to modelpipe, which parses it, dials the ticket
    /// in it, waits for the far machine, and only then presents the code —
    /// the wait that stops a redeem being answered `502` by the tunnel's own
    /// edge before there is a peer to forward it to, which spends the
    /// one-time code on nothing.
    ///
    /// A pipe that comes up somewhere this app will not send a request is
    /// hung up, but the key still comes back: the code was spent to mint it,
    /// and throwing it away would make the person ask the other machine for a
    /// fresh invite to fix something on this one.
    public func pair(pairing string: String, deviceName: String?) async throws -> PairedPipe {
        let paired: Paired
        do {
            paired = try await pairing(string, Self.labelWorthSending(deviceName))
        } catch let error as MpPairError {
            throw Self.refusal(for: error)
        }
        do {
            return PairedPipe(
                session: try ModelpipeSession(pipe: paired.pipe, sleeper: sleeper, grace: grace),
                token: paired.apiKey, device: paired.device)
        } catch {
            await paired.pipe.shutdown()
            return PairedPipe(session: nil, token: paired.apiKey, device: paired.device)
        }
    }

    /// A device name fit to send: trimmed, and nil when that leaves nothing.
    ///
    /// No length cap and no character filter. modelpipe's edge decides both
    /// when it records the name — it drops control and invisible formatting
    /// characters and cuts to 64 — and a cut made here in `Character`s would
    /// not agree with one made there in Unicode scalars.
    static func labelWorthSending(_ deviceName: String?) -> String? {
        guard let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// A pairing error as something worth showing a person.
    ///
    /// Exhaustive and with no `default`, so a case modelpipe adds is a
    /// compile error here rather than a sentence nobody wrote. `message()`
    /// and never `localizedDescription`, for the reason below.
    ///
    /// A refused code keeps its own case. It is the one failure with
    /// somewhere to send the person — the next attempt starts on the other
    /// machine — and `PipeConnectError.pairingRefused` is where the line
    /// saying so is added to modelpipe's sentence.
    static func refusal(for error: MpPairError) -> PipeConnectError {
        switch error {
        case .Refused:
            return .pairingRefused(message: error.message())
        case .NoCode, .BadPairingString, .Unexpected:
            return .dialFailed(message: error.message(), retryable: false)
        case .Dial, .Unreached, .Exchange, .Unknown:
            return .dialFailed(message: error.message(), retryable: error.isRetryable())
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
        case .Bind, .Endpoint, .InvalidRelay, .PeerUnreachable, .Identity, .Unknown:
            return .dialFailed(message: error.message(), retryable: error.isRetryable())
        }
    }
}
