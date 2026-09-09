import GGChatCore
import Modelpipe

// The first thing this module owes the app: the binding's vocabulary said in
// the app's own.
//
// Every `Mp*` translation lives here rather than beside its consumer, so a
// binding release that changed one of them is caught in one place by one
// person reading one file, instead of in whichever call site happened to be
// recompiled first.
//
// The two enums were deliberately built to match, one case for one case, and
// modelpipe-ffi's own documentation says so. That is worth a mapping rather
// than a cast anyway: a match by construction is a promise by the other
// repository, and this is where a release that quietly broke it would be
// caught, in a switch the compiler will not let go stale.
extension PipeStatus {
    /// The same state, in the app's terms.
    ///
    /// Exhaustive and without a `default`, on purpose. A new case on either
    /// side has to be looked at by a person, and a `default` arm is how one
    /// side silently starts reporting a state the other has never heard of —
    /// which for a pipe means a status pill that is confidently wrong rather
    /// than visibly unknown.
    public init(_ status: MpPipeStatus) {
        switch status {
        case .idle: self = .idle
        case .relayed: self = .relayed
        case .direct: self = .direct
        case .closed: self = .closed
        }
    }
}

extension PipeCloseReason {
    /// The binding's reason, in the app's terms — and a third case for the
    /// answer the binding cannot give.
    ///
    /// `MpCloseReason` has two cases and this enum has three, which is the
    /// whole reason this initializer takes an optional. modelpipe records a
    /// reason when somebody asked it to close and when its own listener
    /// stopped accepting; a pipe whose peer simply stopped answering ends
    /// with nothing recorded at all. Read straight through, that `nil` is
    /// indistinguishable from "still open" — so the caller establishes that
    /// the pipe *has* closed, and this maps the remaining silence to the
    /// thing silence actually means.
    ///
    /// Exhaustive and without a `default`, for the reason the status mapping
    /// above gives: a third case arriving from the binding must be looked at
    /// by a person, not folded into `peerVanished` because it happened to be
    /// unrecognised.
    init(_ reason: MpCloseReason?) {
        switch reason {
        case .shutdown?: self = .shutdown
        case .listenerFailed?: self = .listenerFailed
        case nil: self = .peerVanished
        }
    }
}

extension PipeReadings {
    /// The port from the pipe and the counters from its endpoint, in one
    /// value the app can hold without naming a binding type.
    init(port: UInt16, metrics: MpNetworkMetrics) {
        self.init(
            port: port,
            relayConnections: metrics.relayConnections,
            relayConnectionsFailed: metrics.relayConnectionsFailed,
            relayConnectionsRatelimited: metrics.relayConnectionsRatelimited)
    }
}
