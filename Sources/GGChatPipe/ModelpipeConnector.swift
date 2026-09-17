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
    ///
    /// The second argument is where this device keeps its endpoint key for
    /// the machine being dialled, or `nil` to let modelpipe mint one for this
    /// process alone. A path rather than a whole `MpConnectOptions` because it
    /// is the only field of that record this app chooses; the rest are left at
    /// the documented defaults, which is a thing to assert about the real
    /// closure rather than a thing to pass through a fake.
    public typealias Dial = @Sendable (String, String?) async throws -> any MpPipeProtocol

    /// Who reads a ticket before it is dialled. Stateless — no stored
    /// properties, one C call — so one of these is shared rather than made
    /// per dial, and it is not injectable: a fake here would only prove that
    /// a test's own parser agrees with the test.
    static let reader = ModelpipePairingReader()

    // Internal rather than private: `ModelpipeConnector+Pairing.swift` is the
    // other half of this type and reads them, and `private` in Swift reaches
    // only as far as the file.
    let dial: Dial
    let pairing: Pair
    let sleeper: any Sleeper
    let grace: Duration
    let identities: PipeIdentityFiles?

    public init(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200)
    ) {
        self = .live(sleeper: sleeper, grace: grace, identities: .applicationSupport())
    }

    /// The connector exactly as it ships, keeping its keys wherever it is told
    /// to.
    ///
    /// Internal, and apart from the public initialiser, so that a test can
    /// point the real closures at a directory of its own: the two calls below
    /// are the ones a shipped build makes, and a test that built its own
    /// version of them would prove only that it agreed with itself.
    static func live(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200),
        identities: PipeIdentityFiles?
    ) -> ModelpipeConnector {
        // Every other field of `MpConnectOptions` is defaulted and the
        // defaults are the documented right answer. Spelled with its label
        // because uniffi emits the memberwise initialiser in Rust declaration
        // order, so a reordered record silently reorders the arguments here.
        ModelpipeConnector(
            sleeper: sleeper, grace: grace, identities: identities,
            dial: { ticket, identityPath in
                try await mpConnect(
                    ticket: ticket, options: MpConnectOptions(identityPath: identityPath))
            },
            pairing: { pairing, label, identityPath in
                let paired = try await mpPair(
                    pairing: pairing, label: label,
                    options: MpConnectOptions(identityPath: identityPath),
                    reachWithinMs: Self.reachWithinMs)
                return Paired(pipe: paired.pipe, apiKey: paired.apiKey, device: paired.device)
            })
    }

    /// Internal, and `identities` defaults to none: a test that drives a fake
    /// dial says for itself whether this device is keeping a key, and one that
    /// forgot to would otherwise write into the real app's directory.
    init(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200),
        identities: PipeIdentityFiles? = nil,
        dial: @escaping Dial,
        pairing: @escaping Pair = { _, _, _ in
            throw PipeConnectError.unavailable
        }
    ) {
        self.sleeper = sleeper
        self.grace = grace
        self.identities = identities
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
                pipe: try await dialKeepingIdentity(ticket, forMachine: read.ticket),
                sleeper: sleeper, grace: grace)
        } catch let error as MpError {
            throw Self.refusal(for: error)
        }
    }

    /// Dial, carrying this device's key for that machine, and dial once more
    /// without the old key if the key was the thing that stopped it.
    ///
    /// The retry is the only way out of a key file this device cannot use.
    /// modelpipe refuses one that is not a key, or that somebody else can
    /// read, and the sentence it refuses with — choose another path or remove
    /// it — asks for something nobody can do on a phone; a file half written
    /// by a process that was killed is enough to earn it. Throwing that file
    /// away costs this device its fingerprint on the far machine, which
    /// records fingerprints and does not pin them, and buys back a device that
    /// can connect at all.
    ///
    /// Exactly once, and only when there was a file to throw away: a second
    /// refusal is about the directory or the path rather than the key, and
    /// dialling again would fail the same way for as long as anyone let it.
    private func dialKeepingIdentity(
        _ ticket: String, forMachine canonical: String
    ) async throws -> any MpPipeProtocol {
        let identity = identities?.path(forTicket: canonical)
        do {
            return try await dial(ticket, identity)
        } catch let error as MpError {
            guard case .Identity = error, let identity, identities?.discard(at: identity) == true
            else { throw error }
            return try await dial(ticket, identity)
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
