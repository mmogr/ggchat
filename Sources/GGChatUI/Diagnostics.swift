import Foundation
import Observation

/// The distinct tickets this device has connected to, kept locally and
/// shown in Settings. Nothing here leaves the device.
@Observable
public final class Diagnostics {
    public private(set) var ticketDigests: Set<String> = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ticketDigests = Set(defaults.stringArray(forKey: Key.tickets) ?? [])
    }

    /// The app's kill criterion: distinct tickets ever connected to.
    public func recordTicket(digest: String) {
        ticketDigests.insert(digest)
        defaults.set(Array(ticketDigests).sorted(), forKey: Key.tickets)
    }

    private enum Key {
        static let tickets = "diagnostics.ticketDigests"
    }
}
