/// The step that turns a six-digit code into the token
/// ``PipeConnector/connect(ticket:token:)`` needs.
///
/// It sits **before** the seam rather than inside it. The alternative was a
/// third parameter on `connect`, and the seam is the one thing
/// `modelpipe-ffi` has to implement unchanged (ADR 0001), so the pairing
/// round trip is built out of the seam instead of added to it: dial with
/// the ticket, wait for the far machine, redeem through the port that dial
/// bound, hang up.
///
/// The far machine's pairing route is only reachable *through* the pipe —
/// that is the whole point of it, since a code shouted over the internet
/// would be worth nothing — so there is no way to pair without a dial.
public struct PipePairing: Sendable {
    private let connector: any PipeConnector
    private let redeemer: any PairingRedeemer
    private let sleeper: any Sleeper
    private let patience: Duration

    /// - Parameters:
    ///   - connector: how the ticket is dialled.
    ///   - redeemer: how the code is traded for the key.
    ///   - sleeper: how the wait for the far machine is timed.
    ///   - patience: how long to wait for the far machine before giving up.
    ///     Thirty seconds because that is roughly what iroh spends failing to
    ///     reach a machine that is switched off, so a shorter wait would give
    ///     up on a slow network and a longer one would hang on a dead one.
    ///     gglib's own connect side waits exactly this long for the same
    ///     reason.
    public init(
        connector: any PipeConnector,
        redeemer: any PairingRedeemer = HTTPPairingRedeemer(),
        sleeper: any Sleeper = ContinuousClockSleeper(),
        patience: Duration = .seconds(30)
    ) {
        self.connector = connector
        self.redeemer = redeemer
        self.sleeper = sleeper
        self.patience = patience
    }

    /// Dial `ticket`, reach the far machine, redeem `code` through it, and
    /// hand back that machine's API key.
    ///
    /// The pairing session is shut down either way, and the caller dials
    /// again with the key. That is one extra dial, spent once per machine,
    /// and it buys two things: the seam keeps its two parameters, and the
    /// steady-state path — the one every later launch takes — is walked
    /// while the person who typed the code is still watching.
    ///
    /// The dial carries the code as its token because during pairing the
    /// code *is* the only credential this side holds; it is what the redeem
    /// request bears. modelpipe's own connect takes no token at all.
    ///
    /// `deviceName` rides along with the redeem. It is what the far machine
    /// will list this device as, if it keeps a list, and not the provider's
    /// name, which is what this side calls the far machine.
    public func token(ticket: String, code: String, deviceName: String? = nil) async throws -> String {
        let session = try await connector.connect(ticket: ticket, token: code)
        do {
            try await reachFarMachine(through: session)
            let key = try await redeemer.redeem(code: code, deviceName: deviceName, through: session.baseURL)
            await session.shutdown()
            return key
        } catch {
            // A refused code must not leave a pipe up. There is nothing to
            // retry through it: the code is spent or wrong, and the next
            // attempt starts with a fresh `gglib remote enable`.
            await session.shutdown()
            throw error
        }
    }

    /// Waits until the pipe has actually reached the other end.
    ///
    /// This is the whole difference between a pairing that works and one that
    /// burns the code. `connect` returns as soon as the **local port is
    /// bound**, not once the far machine answers — that is modelpipe's
    /// contract and the seam says so — and a redeem sent into that gap is
    /// answered `502` by the tunnel's own edge, because there is no peer to
    /// forward it to. The code is spent on that 502 and the next attempt
    /// needs a fresh `gglib remote enable`.
    ///
    /// It is not a rare race. A hole punch through carrier-grade NAT took
    /// about two seconds to its first path when this was measured, and the
    /// redeem goes out in microseconds — so on a phone the gap is lost
    /// almost every time, while on a fast LAN it is won often enough to look
    /// like the code was simply wrong. gglib's own connect side has waited
    /// here from the start (`first_contact.rs`, "a redeem sent now would
    /// spend the one-time code on the 502 the edge answers while there is no
    /// peer"); this side had the same seam in front of it and did not.
    ///
    /// `relayed` counts as reached. Traffic through a relay is still
    /// end-to-end encrypted and the pairing route does not care which path it
    /// took, so waiting for `direct` would fail on exactly the networks the
    /// relay exists for.
    private func reachFarMachine(through session: any PipeSession) async throws {
        let reached = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await status in session.status where status.isConnected {
                    return true
                }
                // The stream ended without ever connecting, which is a pipe
                // that closed rather than one still trying.
                return false
            }
            group.addTask { [sleeper, patience] in
                // Time is an argument here as everywhere else in Core, so a
                // test can run this without waiting thirty seconds.
                try? await sleeper.sleep(for: patience)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard reached else {
            throw PairingError.unreachable(
                "the other machine did not answer in time, so the code was not spent")
        }
    }
}
