import Foundation

/// The seam between the app and modelpipe. `MockPipeConnector` implements it
/// today; `ModelpipeConnector` will implement it when `modelpipe-ffi` lands,
/// and nothing above this protocol changes.
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

    public var errorDescription: String? {
        switch self {
        case .invalidTicket(let shape): shape.errorDescription
        case .missingToken: "A token is required alongside the ticket."
        }
    }
}
