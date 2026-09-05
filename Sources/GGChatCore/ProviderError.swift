import Foundation

/// Which machine the user should look at when a request fails. modelpipe's
/// and gglib's error codes already say this; the UI shows it as a second line.
public enum WhereToLook: Sendable, Equatable {
    case servingSide
    case connectingSide
    case request
    case unknown
}

public enum ProviderError: Error, Sendable, Equatable, LocalizedError {
    /// A non-2xx reply. `message` is the server's own sentence, shown verbatim.
    case server(status: Int, code: String?, message: String)
    /// The request never completed: DNS, refused, dropped mid-stream.
    case transport(String)
    case decoding(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .server(_, _, let message): message
        case .transport(let detail): "Could not reach the server: \(detail)"
        case .decoding(let detail): "The server sent something this app could not read: \(detail)"
        case .invalidResponse(let detail): "The server did not answer as an HTTP server: \(detail)"
        }
    }

    public var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    public var whereToLook: WhereToLook {
        switch self {
        case .server(_, let code, _): Self.whereToLook(forCode: code)
        case .transport: .connectingSide
        case .decoding, .invalidResponse: .unknown
        }
    }

    /// modelpipe (`docs`) and gglib codes. Unknown codes pass through.
    public static func whereToLook(forCode code: String?) -> WhereToLook {
        switch code {
        case "invalid_api_key", "backend_unreachable":
            .servingSide
        case "tunnel_unavailable", "bad_gateway":
            .connectingSide
        case "bad_request", "incomplete_request", "loop_detected", "stagnation_detected",
            "profile_not_found", "model_not_found", "invalid_request":
            .request
        default:
            .unknown
        }
    }
}

extension WhereToLook {
    /// The second line under an error, or nil when there is nothing to add.
    public var hint: String? {
        switch self {
        case .servingSide: "Look at the machine that is serving the model."
        case .connectingSide: "Look at this device's connection."
        case .request: "The request itself was refused; change it and try again."
        case .unknown: nil
        }
    }
}
