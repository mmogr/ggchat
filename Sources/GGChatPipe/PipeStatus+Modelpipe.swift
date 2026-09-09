import GGChatCore
import Modelpipe

// The first thing this module owes the app: the binding's four status values
// said in the app's own vocabulary.
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
