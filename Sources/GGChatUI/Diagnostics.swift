import Foundation
import GGChatCore
import Observation

/// The readings the ADRs name, kept locally and shown in Settings with
/// their denominators. Nothing here leaves the device.
@Observable
public final class Diagnostics {
    public private(set) var foregroundResumes = 0
    public private(set) var transportErrorsAfterResume = 0
    public private(set) var closedWhileStreaming = 0
    public private(set) var closedTransitions = 0
    public private(set) var continuePresses = 0
    public private(set) var ticketDigests: Set<String> = []

    private let defaults: UserDefaults
    private var lastResume: Date?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        foregroundResumes = defaults.integer(forKey: Key.resumes)
        transportErrorsAfterResume = defaults.integer(forKey: Key.resumeErrors)
        closedWhileStreaming = defaults.integer(forKey: Key.closedStreaming)
        closedTransitions = defaults.integer(forKey: Key.closed)
        continuePresses = defaults.integer(forKey: Key.continues)
        ticketDigests = Set(defaults.stringArray(forKey: Key.tickets) ?? [])
    }

    /// ADR 0001: a transport error within five seconds of a resume.
    public func recordResume(at now: Date) {
        lastResume = now
        foregroundResumes += 1
        defaults.set(foregroundResumes, forKey: Key.resumes)
    }

    public func recordStreamEnd(with error: ProviderError?, at now: Date) {
        guard case .transport? = error, let lastResume, now.timeIntervalSince(lastResume) < 5 else { return }
        transportErrorsAfterResume += 1
        defaults.set(transportErrorsAfterResume, forKey: Key.resumeErrors)
    }

    /// ADR 0002: closes seen while a reply was streaming, against Continue presses.
    public func recordClosed(whileStreaming: Bool) {
        closedTransitions += 1
        defaults.set(closedTransitions, forKey: Key.closed)
        if whileStreaming {
            closedWhileStreaming += 1
            defaults.set(closedWhileStreaming, forKey: Key.closedStreaming)
        }
    }

    public func recordContinue() {
        continuePresses += 1
        defaults.set(continuePresses, forKey: Key.continues)
    }

    /// The app's kill criterion: distinct tickets ever connected to.
    public func recordTicket(digest: String) {
        ticketDigests.insert(digest)
        defaults.set(Array(ticketDigests).sorted(), forKey: Key.tickets)
    }

    private enum Key {
        static let resumes = "diagnostics.foregroundResumes"
        static let resumeErrors = "diagnostics.transportErrorsAfterResume"
        static let closedStreaming = "diagnostics.closedWhileStreaming"
        static let closed = "diagnostics.closedTransitions"
        static let continues = "diagnostics.continuePresses"
        static let tickets = "diagnostics.ticketDigests"
    }
}
