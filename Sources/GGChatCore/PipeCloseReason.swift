/// Why a pipe stopped carrying traffic.
///
/// Three cases where the binding has two. modelpipe reports a shutdown and a
/// failed listener and nothing else, so a pipe whose peer simply stopped
/// answering closes with no reason recorded at all. That silence is the close
/// a person most wants explained — a laptop that slept, a machine carried out
/// of range — which is why it is named here rather than left as the absence
/// of a reason.
///
/// Stated in this module's own words and not the binding's, because the
/// binding's vocabulary does not cross the seam: only `GGChatPipe` may name
/// it, and everything above the seam has to be able to say why a pipe closed.
public enum PipeCloseReason: Sendable, Equatable, CaseIterable {
    /// This app asked, or the far side hung up cleanly.
    case shutdown

    /// The local listener stopped accepting. The pipe is gone for a reason
    /// that is this device's, not the network's.
    case listenerFailed

    /// The pipe ended and nothing recorded why, which is what a peer that
    /// stopped answering looks like from this side.
    case peerVanished

    /// What to tell the person, or `nil` when this app is what closed it.
    ///
    /// A hang-up the app performed — going to the background, a re-dial the
    /// person pressed, a provider deleted — is not news, and a sentence about
    /// it would be an alert raised for something the person had just done
    /// themselves. The other two are worth saying, and each names a side to
    /// look at rather than describing the failure in the abstract.
    public func sentence(naming machine: String) -> String? {
        switch self {
        case .shutdown: nil
        case .listenerFailed: "This device stopped accepting the connection to \(machine)."
        case .peerVanished: "\(machine) stopped answering."
        }
    }

    /// Whether this close is worth doing something about on its own.
    ///
    /// The distinction a re-dial is built on: a pipe this app hung up should
    /// stay hung up, and a pipe that went away without being asked is the one
    /// worth trying again.
    public var wasUnexpected: Bool { self != .shutdown }
}
