import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Why a pairing code did not become a key. Each case is a sentence, and
/// each blames the right thing: the code, the network, or the far machine.
public enum PairingError: Error, Sendable, Equatable, LocalizedError {
    /// The far machine said no. It is a flat 401 there on purpose — wrong,
    /// expired, spent and burned are one answer, so that a guesser learns
    /// nothing from which refusal they got — so this case is one sentence
    /// listing the reasons it could have been.
    case refused
    /// The request never got through. Mostly that is the far machine not
    /// answering — the pipe itself is up, since the code went to its own
    /// loopback port — and it also covers a request that could not be
    /// written, which one string field makes effectively impossible.
    case unreachable(String)
    /// A reply that was neither the key nor the refusal.
    case unexpectedStatus(Int)
    /// A 200 whose body was not `{"api_key": …}`.
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .refused:
            "The other machine refused the pairing code. It may have expired (two minutes), been used "
                + "already, or been burned by wrong attempts; run `gglib remote enable` there again."
        case .unreachable(let detail):
            "The pairing request did not get through: \(detail)"
        case .unexpectedStatus(let status):
            "The pairing request was answered with HTTP \(status)."
        case .malformedResponse(let detail):
            "The pairing response was not what was expected: \(detail)"
        }
    }
}

/// Trades a one-time pairing code for the machine's API key.
///
/// A seam of its own so the app model can be tested without a server, and
/// so the one place that speaks gglib's pairing route is named.
public protocol PairingRedeemer: Sendable {
    /// POST the code to `baseURL`'s pairing route and return the API key.
    /// `baseURL` is a live pipe's loopback URL: the request is what makes
    /// the far machine's route reachable at all.
    func redeem(code: String, through baseURL: URL) async throws -> String
}

/// The real one: `POST <baseURL>/remote/pair`, the Swift half of gglib's
/// `remote/redeem.rs`.
public struct HTTPPairingRedeemer: PairingRedeemer {
    /// How long the exchange may take end to end. Generous because a first
    /// request through a fresh pipe may still be finishing the hole punch;
    /// bounded because a tunnel that never answers is a failure to report,
    /// not to wait out. gglib's own redeem waits exactly this long.
    public static let timeout: TimeInterval = 20

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Trade the code for the key.
    ///
    /// The code travels twice on purpose: as the bearer, so the tunnel
    /// edge's one-time grant admits a request that has no real token yet,
    /// and in the body, so the far proxy's pairing route can check it
    /// against the code that session minted. Both halves are required
    /// there; sending one is refused exactly like sending neither.
    public func redeem(code: String, through baseURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "remote/pair"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(PairRequest(code: code))
        } catch {
            // One string field, so this cannot happen — but every failure
            // out of here is a `PairingError` with a sentence, and letting
            // an `EncodingError` past would break that for no gain.
            throw PairingError.unreachable("the request could not be written: \(error)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PairingError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PairingError.malformedResponse(String(describing: type(of: response)))
        }
        // 401 first, because it is the only refusal the route has and it is
        // about the code rather than about the exchange.
        if http.statusCode == 401 { throw PairingError.refused }
        guard (200..<300).contains(http.statusCode) else {
            throw PairingError.unexpectedStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(PairResponse.self, from: data).apiKey
        } catch {
            throw PairingError.malformedResponse(String(describing: error))
        }
    }

    private struct PairRequest: Encodable {
        var code: String
    }

    private struct PairResponse: Decodable {
        var apiKey: String

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
        }
    }
}
