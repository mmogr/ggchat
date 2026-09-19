import Foundation
import GGChatCore
import Modelpipe

/// The other half of ModelpipeConnector: a pairing string in, a key and
/// the pipe it was redeemed over out.
///
/// A file of its own because the two halves together are over this repo's
/// file-size limit, and this is where the seam already ran: dialling is what
/// a device does every day with a key it holds, pairing is the once-per-
/// machine exchange that mints one. `ModelpipeConnectorTests` and
/// `ModelpipeConnectorPairingTests` were split along the same line, for the
/// same reason, before this file existed.
extension ModelpipeConnector {
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
    /// Defaults to modelpipe's own `mpPair`. The label is this device's name
    /// for the far machine's list; the third argument is the identity file, as
    /// on ``Dial``, so that the device the far machine records as it mints the
    /// key is the one that then chats through the pipe.
    public typealias Pair = @Sendable (String, String?, String?) async throws -> Paired

    /// How long the far machine has to answer the dial the code is redeemed
    /// over. Thirty seconds because that is roughly what iroh spends failing
    /// to reach a machine that is switched off, and it is what gglib's own
    /// connect side waits. modelpipe adds its own fixed deadline for the
    /// redeem itself once the pipe is up.
    public static let reachWithinMs: UInt64 = 30_000

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
    ///
    /// It carries the same identity file a dial to that machine would, so the
    /// endpoint recorded beside the key as it is minted is the one that then
    /// chats, rather than one that lived for the length of the exchange.
    /// Unlike a dial it cannot throw an unusable key away and try
    /// again: `MpPairError` folds every transport failure into one case
    /// carrying a sentence, so a pairing cannot tell an unusable key from a
    /// machine that is switched off without reading modelpipe's words back,
    /// and matching on wording is how this project has been caught before. A
    /// key half written is still healed, because the path is built the same
    /// way for both; a key corrupt in some other way is met by the next dial
    /// to that machine, which does heal. The PR body lists it. The one match
    /// on wording in this file, `tooOldToPairAnswer`, only chooses which
    /// line a failure's sentence gets, and says why that much is tolerable.
    public func pair(pairing pairingString: String, deviceName: String?) async throws -> PairedPipe {
        let paired: Paired
        do {
            paired = try await pairing(
                pairingString, Self.labelWorthSending(deviceName), identityForPairing(pairingString))
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

    /// Which identity file a pairing string's machine has, if it can be read
    /// at all.
    ///
    /// A string this app cannot read is handed over with no identity rather
    /// than refused here. modelpipe is about to read the same string and
    /// refuse it in its own words, which is the one place that sentence is
    /// written; refusing it here first would be the second copy of that
    /// mapping the reader exists to prevent, and it would answer a person who
    /// typed a bad code with a different sentence depending on which of two
    /// parsers saw it first.
    private func identityForPairing(_ pairingString: String) -> String? {
        guard case .success(let readPairing) = Self.reader.read(pairingString) else { return nil }
        return identities?.path(forTicket: readPairing.ticket)
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
    /// Three failures keep cases of their own, because each has somewhere to
    /// send the person, and `PipeConnectError` is where the line saying so is
    /// added to modelpipe's sentence. A refused code: the next attempt starts
    /// on the other machine. The answer a desktop on gglib 0.18 gives: that
    /// desktop has to be updated first. Any other answer that is not a
    /// pairing answer: the code may be gone.
    static func refusal(for error: MpPairError) -> PipeConnectError {
        switch error {
        case .Refused:
            return .pairingRefused(message: error.message())
        case .Unexpected(let detail) where detail == Self.tooOldToPairAnswer:
            return .desktopTooOldToPair(message: error.message())
        case .Unexpected:
            return .unexpectedAnswer(message: error.message())
        case .NoCode, .BadPairingString:
            return .dialFailed(message: error.message(), retryable: false)
        case .Dial, .Unreached, .Exchange, .Unknown:
            return .dialFailed(message: error.message(), retryable: error.isRetryable())
        }
    }

    /// What modelpipe 0.6's `pair` reports, as `MpPairError.Unexpected`'s
    /// detail, when the far machine answers the code with any status other
    /// than 200, 401 or 502. A desktop on gglib 0.18 answers that way: its
    /// edge spends the code and hands the request to a proxy with no such
    /// route.
    ///
    /// Matched on its wording, which `pair(pairing:deviceName:)` warns
    /// against, because the wording is all `Unexpected` carries. It is
    /// tolerable here where it was not for healing an identity: a stale
    /// match deletes nothing and only chooses which line to add. If a later
    /// modelpipe rewords it, the answer falls to `unexpectedAnswer`, which
    /// still says the code may have been spent. It was read at modelpipe
    /// 0.6.0 through modelpipe-ffi 0.3.0, and wants reading again when the
    /// binding moves. gglib's own `join` matches the same words, from gglib
    /// `61e06b57` (#1087) on.
    static let tooOldToPairAnswer = "a status other than 200 or 401"
}

/// The key stays out of what the value prints: interpolated, reflected
/// or dumped, a `Paired` shows the device and `<redacted>` in the key's
/// place, as `MpPaired`'s own description does.
extension ModelpipeConnector.Paired: CustomStringConvertible, CustomReflectable {
    public var description: String { "Paired(device: \(device), apiKey: <redacted>)" }

    public var customMirror: Mirror {
        Mirror(self, children: ["device": device, "apiKey": "<redacted>"], displayStyle: .struct)
    }
}
