import Foundation

/// The step that turns a six-digit code into the token
/// ``PipeConnector/connect(ticket:token:)`` needs.
///
/// It sits **before** the seam rather than inside it. The alternative was a
/// third parameter on `connect`, and the seam is the one thing
/// `modelpipe-ffi` has to implement unchanged (ADR 0001), so the pairing
/// round trip is built out of the seam instead of added to it: dial with
/// the ticket, redeem through the port that dial bound, hang up.
///
/// The far machine's pairing route is only reachable *through* the pipe —
/// that is the whole point of it, since a code shouted over the internet
/// would be worth nothing — so there is no way to pair without a dial.
public struct PipePairing: Sendable {
    private let connector: any PipeConnector
    private let redeemer: any PairingRedeemer

    public init(connector: any PipeConnector, redeemer: any PairingRedeemer = HTTPPairingRedeemer()) {
        self.connector = connector
        self.redeemer = redeemer
    }

    /// Dial `ticket`, redeem `code` through it, and hand back the far
    /// machine's API key.
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
    public func token(ticket: String, code: String) async throws -> String {
        let session = try await connector.connect(ticket: ticket, token: code)
        do {
            let key = try await redeemer.redeem(code: code, through: session.baseURL)
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
}
