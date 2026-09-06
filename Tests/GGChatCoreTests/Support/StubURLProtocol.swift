import Foundation
import Synchronization

/// Serves canned HTTP responses keyed by host and path, so provider tests
/// never touch the network. Each test uses its own host.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status: Int
        var headers: [String: String] = ["Content-Type": "application/json"]
        var chunks: [Data]
    }

    private static let stubs = Mutex<[String: [String: Stub]]>([:])
    private static let seen = Mutex<[URLRequest]>([])

    static func register(host: String, path: String, _ stub: Stub) {
        stubs.withLock { $0[host, default: [:]][path] = stub }
    }

    static func requests(host: String) -> [URLRequest] {
        seen.withLock { $0.filter { $0.url?.host() == host } }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.withLock { $0.append(request) }
        guard let url = request.url, let host = url.host(),
            let stub = Self.stubs.withLock({ $0[host]?[url.path()] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in stub.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
