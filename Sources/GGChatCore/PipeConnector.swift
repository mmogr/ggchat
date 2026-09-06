import Foundation

/// The seam between the app and modelpipe. `MockPipeConnector` implements it
/// in DEBUG builds and `UnavailablePipeConnector` in every other build;
/// `ModelpipeConnector` will implement it when `modelpipe-ffi` lands, and
/// nothing above this protocol changes.
public protocol PipeConnector: Sendable {
    func connect(ticket: String, token: String) async throws -> any PipeSession
}

/// A live pipe. Requests go to `baseURL` through an ordinary
/// `OpenAICompatibleProvider`; there is no pipe-specific chat code.
public protocol PipeSession: Sendable {
    /// `http://127.0.0.1:<port>/v1`
    var baseURL: URL { get }
    /// Current value first, then every change.
    var status: AsyncStream<PipeStatus> { get }
    func shutdown() async
}

/// Why a connect attempt was refused before anything was dialled.
public enum PipeConnectError: Error, Sendable, Equatable, LocalizedError {
    case invalidTicket(TicketShapeError)
    case missingToken
    /// Nothing in this build can dial a ticket. The ticket and the token were
    /// fine; the build has no `modelpipe-ffi` behind the seam, and the mock
    /// that stands in for it is DEBUG-only.
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidTicket(let shape): shape.errorDescription
        case .missingToken: "A token is required alongside the ticket."
        case .unavailable: "This build cannot open a pipe yet; add the machine by its address instead."
        }
    }
}
