/// The state of a modelpipe connection as the app sees it.
///
/// `direct` means a peer-to-peer path; `relayed` means traffic is going via a
/// relay and is still end-to-end encrypted. The UI shows the difference
/// quietly.
public enum PipeStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case idle
    case direct
    case relayed
    case closed

    /// Whether requests can be expected to reach the other side right now.
    public var isConnected: Bool {
        switch self {
        case .direct, .relayed: true
        case .idle, .closed: false
        }
    }
}
