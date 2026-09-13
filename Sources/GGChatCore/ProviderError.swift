import Foundation

/// Which machine the user should look at when a request fails. modelpipe's
/// and gglib's error codes already say this; the UI shows it as a second line.
///
/// The raw values are stored: the message that ended a turn keeps the
/// ``Failure`` that ended it, and this is part of it. Renaming a case would
/// turn every failure saved with it into `.unknown`, so `ErrorTests` pins the
/// five strings.
public enum WhereToLook: String, Codable, Sendable, Equatable, Hashable {
    case servingSide
    case connectingSide
    case request
    /// Neither machine is broken and the request was fine: something over
    /// there is busy or still starting, and the same request works shortly.
    /// Sending someone to look at a machine that is doing its job is worse
    /// than saying nothing.
    case waitAndRetry
    case unknown
}

public enum ProviderError: Error, Sendable, Equatable, LocalizedError {
    /// A non-2xx reply. `message` is the server's own sentence, shown verbatim.
    case server(status: Int, code: String?, message: String)
    /// An error the server wrote into a stream it had already begun with a
    /// `200`: gglib's `upstream_error` and `upstream_timeout`, written as a
    /// bare `{"error":…}` event (`gglib-core/src/sse/encoder.rs`,
    /// `upstream_error_frame`). Not a `.server`, which is a reply that was
    /// refused outright; this one usually has some of the reply before it.
    case stream(code: String?, message: String)
    /// The request never completed: DNS, refused, dropped mid-stream.
    case transport(String)
    case decoding(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .server(_, _, let message): message
        // Framed, like `.transport`: gglib's message here is often a socket
        // sentence ("error decoding response body") that reads as nothing
        // on its own.
        case .stream(_, let message): "The reply stopped: \(message)"
        case .transport(let detail): "Could not reach the server: \(detail)"
        case .decoding(let detail): "The server sent something this app could not read: \(detail)"
        case .invalidResponse(let detail): "The server did not answer as an HTTP server: \(detail)"
        }
    }

    public var code: String? {
        switch self {
        case .server(_, let code, _), .stream(let code, _): code
        case .transport, .decoding, .invalidResponse: nil
        }
    }

    public var whereToLook: WhereToLook {
        switch self {
        case .server(_, let code, _), .stream(let code, _): Self.whereToLook(forCode: code)
        case .transport: .connectingSide
        case .decoding, .invalidResponse: .unknown
        }
    }

    /// The vocabulary is closed; the wire is not. A code from neither
    /// modelpipe nor gglib — a proxy in between, a future release — passes
    /// through as `.unknown` rather than being guessed at.
    public static func whereToLook(forCode code: String?) -> WhereToLook {
        guard let code, let known = Code(rawValue: code) else { return .unknown }
        return known.whereToLook
    }

    /// The second line under a failure with this code: the code's own
    /// sentence where it has one, then the side the code names today, and
    /// `side` only for a failure with no code this build knows. A saved
    /// failure is drawn by this build's reading of its code, so a better one
    /// reaches old conversations too.
    public static func hint(forCode code: String?, on side: WhereToLook) -> String? {
        guard let known = code.flatMap(Code.init(rawValue:)) else { return side.hint }
        return known.hint ?? known.whereToLook.hint
    }

    /// The second line under this error.
    public var hint: String? {
        Self.hint(forCode: code, on: whereToLook)
    }
}

extension ProviderError {
    /// Every error code modelpipe and gglib write, as a closed vocabulary.
    ///
    /// It was a `switch` over string literals with a `default`, which meant a
    /// code nobody had thought about was indistinguishable from a code from
    /// somewhere else, and the only thing guarding against that was a
    /// hand-written list in a test — a list that named ten codes while the
    /// switch handled eleven. As an enum the mapping below is exhaustive by
    /// the compiler and `allCases` *is* the list, so neither can drift again.
    public enum Code: String, CaseIterable, Sendable {
        // modelpipe, `modelpipe/src/refusal.rs`. All six are synthesized at
        // the edge and never relayed, so which side of the tunnel wrote one
        // is knowable, and is the whole answer.
        case invalidAPIKey = "invalid_api_key"
        case badRequest = "bad_request"
        case badGateway = "bad_gateway"
        case backendUnreachable = "backend_unreachable"
        case tunnelUnavailable = "tunnel_unavailable"
        case incompleteRequest = "incomplete_request"

        // gglib, `gglib-proxy`'s `ErrorResponse` constructors plus the
        // `upstream_timeout` it writes into a stream that has already begun.
        case admissionTimeout = "admission_timeout"
        case contextLengthExceeded = "context_length_exceeded"
        case deviceNotPaired = "device_not_paired"
        case embeddingModelCannotChat = "embedding_model_cannot_chat"
        case hostNotAllowed = "host_not_allowed"
        case internalError = "internal_error"
        case invalidPairingCode = "invalid_pairing_code"
        case invalidRequest = "invalid_request"
        case loopDetected = "loop_detected"
        case mcpNotAllowedOverTunnel = "mcp_not_allowed_over_tunnel"
        case modelFileNotFound = "model_file_not_found"
        case modelLoading = "model_loading"
        case modelNotFound = "model_not_found"
        case notAnEmbeddingModel = "not_an_embedding_model"
        case pinnedModelMismatch = "pinned_model_mismatch"
        case profileNotFound = "profile_not_found"
        case stagnationDetected = "stagnation_detected"
        case upstreamError = "upstream_error"
        case upstreamTimeout = "upstream_timeout"
    }
}

extension ProviderError.Code {
    /// Where the person reading this should look. No `default`: a code added
    /// above without an answer here does not compile.
    public var whereToLook: WhereToLook {
        switch self {
        // Written on the machine with the models, and fixable only there.
        // `bad_gateway` reads like a tunnel failure and is not one: modelpipe
        // writes it on the *serve* side, about a backend it did reach and
        // could not read (`modelpipe/src/exchange.rs:240,257`). Filing it
        // under the connecting side sent people to check their phone's signal
        // while the model server was the thing that was wedged.
        // `invalid_api_key` is here for the same kind of reason: both doors
        // it can fail at, modelpipe's bearer check and gglib's, stand on the
        // serving machine.
        // `device_not_paired` reads like this device's fault and is not one.
        // gglib's device gate writes it, on the serving machine, when the
        // tunnel let a request in without naming a device — a pairing code
        // used as a key, most likely — and the code that fixes it is handed
        // out there. A device that machine has forgotten never gets this far:
        // the edge refuses its key first, with `invalid_api_key`.
        case .invalidAPIKey, .badGateway, .backendUnreachable, .deviceNotPaired, .hostNotAllowed, .internalError,
            .invalidPairingCode, .mcpNotAllowedOverTunnel, .modelFileNotFound, .upstreamError:
            .servingSide

        // Written on this device, about this device's reach.
        // `incomplete_request` reads like a bad request and is not one:
        // modelpipe can only write it once the head has already gone
        // upstream, so it says the request was fine and the upload stopped.
        // That is the network here, not the JSON.
        case .tunnelUnavailable, .incompleteRequest:
            .connectingSide

        // The request itself, answerable by sending a different one.
        case .badRequest, .contextLengthExceeded, .embeddingModelCannotChat, .invalidRequest,
            .loopDetected, .modelNotFound, .notAnEmbeddingModel, .pinnedModelMismatch,
            .profileNotFound, .stagnationDetected:
            .request

        // Nothing is wrong yet: a model still loading, a queue that did not
        // reach this request in time, a first byte that has not arrived.
        case .admissionTimeout, .modelLoading, .upstreamTimeout:
            .waitAndRetry
        }
    }
}

extension ProviderError.Code {
    /// A sentence of the code's own, for the few whose side alone would send
    /// someone the wrong way, and nil for the rest, which say where to look
    /// and nothing more. No `default`, for `whereToLook`'s reason: a code
    /// added above is looked at here too.
    ///
    /// `invalid_api_key` is the one so far. "Look at the machine that is
    /// serving the model" is true of it and no help: the machine is doing its
    /// job, and what is wrong is the key this app sent. The sentence is the
    /// condition only, and true of a pipe and a server alike. Where a new key
    /// comes from depends on the kind of provider, which Core does not know,
    /// so the app says that beside it.
    public var hint: String? {
        switch self {
        case .invalidAPIKey:
            "The serving machine did not accept the key this app sent."
        case .badRequest, .badGateway, .backendUnreachable, .tunnelUnavailable, .incompleteRequest,
            .admissionTimeout, .contextLengthExceeded, .deviceNotPaired, .embeddingModelCannotChat,
            .hostNotAllowed, .internalError, .invalidPairingCode, .invalidRequest, .loopDetected,
            .mcpNotAllowedOverTunnel, .modelFileNotFound, .modelLoading, .modelNotFound,
            .notAnEmbeddingModel, .pinnedModelMismatch, .profileNotFound, .stagnationDetected,
            .upstreamError, .upstreamTimeout:
            nil
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
        case .waitAndRetry: "The serving machine is busy or still starting; try again in a moment."
        case .unknown: nil
        }
    }
}
