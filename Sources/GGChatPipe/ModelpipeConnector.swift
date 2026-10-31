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
    /// The second argument is the directory this device keeps its endpoint
    /// keys in, or `nil` to let modelpipe mint one for this process alone.
    /// A directory and not a file: the binding names the file itself, from
    /// the ticket it is about to dial. A path rather than a whole
    /// `MpConnectOptions` because it is the only field of that record that
    /// changes from one dial to the next; the rest are `DialOptions`, fixed
    /// when `live(sleeper:grace:identities:options:)` builds the real
    /// closure, which is a thing to assert about that closure rather than a
    /// thing to pass through a fake.
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
    /// to and dialling with whatever ``DialOptions`` it is handed.
    ///
    /// Internal, and apart from the public initialiser, so that a test can
    /// point the real closures at a directory of its own and at a network of
    /// its own: the two calls below are the ones a shipped build makes, and a
    /// test that built its own version of them would prove only that it
    /// agreed with itself. The options are the one thing such a test has to
    /// change. `RealPipeTests` dials a `modelpipe serve` on this machine with
    /// discovery, port mapping and the public relays all off, so the pairing
    /// forms over the ticket's own addresses and nothing past this machine is
    /// asked; everything else it runs is the shipped path.
    static func live(
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200),
        identities: PipeIdentityFiles?,
        options: DialOptions = .shipped
    ) -> ModelpipeConnector {
        ModelpipeConnector(
            sleeper: sleeper, grace: grace, identities: identities,
            dial: { ticket, identityDir in
                try await mpConnect(ticket: ticket, options: options.connectOptions(identityDir: identityDir))
            },
            pairing: { pairing, label, identityDir in
                let paired = try await mpPair(
                    pairing: pairing, label: label,
                    options: options.connectOptions(identityDir: identityDir),
                    reachWithinMs: Self.reachWithinMs)
                return Paired(pipe: paired.pipe, apiKey: paired.apiKey, device: paired.device)
            })
    }

    /// What a dial asks of the network beyond the ticket it was handed.
    ///
    /// Three fields of `MpConnectOptions` and not the record itself: the
    /// identity directory is the connector's to fill in per dial, and the
    /// fields left out are ones nothing here has a reason to choose.
    struct DialOptions: Sendable, Equatable {
        /// Resolve the far machine through n0's discovery service.
        var discovery: Bool
        /// Ask the router to map a port.
        var portMapping: Bool
        /// A relay of this side's own, or `nil` for the public ones.
        var relayURL: String?

        /// What a shipped build dials with, which is whatever the binding
        /// defaults to: read from a default `MpConnectOptions` rather than
        /// written out here, so a release of the binding that changes a
        /// default changes it for the app as well, as it did before these
        /// options existed.
        static var shipped: DialOptions {
            let defaults = MpConnectOptions()
            return DialOptions(
                discovery: defaults.discovery, portMapping: defaults.portMapping, relayURL: defaults.relayUrl)
        }

        /// The record `mpConnect` and `mpPair` take. Each field is set by
        /// name: uniffi emits the memberwise initialiser in Rust declaration
        /// order, so a reordered record would silently reorder positional
        /// arguments here.
        func connectOptions(identityDir: String?) -> MpConnectOptions {
            var options = MpConnectOptions(identityDir: identityDir)
            options.discovery = discovery
            options.portMapping = portMapping
            options.relayUrl = relayURL
            return options
        }
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
        let readPairing: ReadPairing
        switch Self.reader.read(ticket) {
        case .success(let pairingReading):
            readPairing = pairingReading
        case .failure(.malformed(let message)):
            throw PipeConnectError.invalidTicket(message: message)
        }
        guard !readPairing.hasCode else {
            throw PipeConnectError.invalidTicket(
                message: "That string carries a pairing code. A code is redeemed once, not dialled; "
                    + "add the machine with it instead of storing it as a ticket.")
        }
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PipeConnectError.missingToken
        }
        // The dial carries the directory, not a file. Naming the file from
        // the ticket is the binding's, and so is throwing away a key this
        // device cannot use and minting another — which this type used to do
        // here, and could only do while it knew the name.
        do {
            return try ModelpipeSession(
                pipe: try await dial(ticket, identities?.directoryPath()),
                sleeper: sleeper, grace: grace)
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
        case .Bind, .Endpoint, .InvalidRelay, .PeerUnreachable, .Identity, .Unknown:
            return .dialFailed(message: error.message(), retryable: error.isRetryable())
        }
    }
}
