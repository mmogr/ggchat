import Foundation
import GGChatCore
import Synchronization

/// The far side of a mock pipe, for the model list: answers `GET /v1/models`
/// the way it is told to at each host, and `GET /v1/proxy/status` with a pane.
/// Each test uses its own host.
///
/// A mock pipe hands out whatever provider it was built with, so an
/// `OpenAICompatibleProvider` over this is a pipe whose far machine is gglib
/// with one model, Qwen3.8-27B.
final class ModelsServer: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        /// The model list.
        case listing
        /// What this device's own end of the pipe answers while the far
        /// machine is not reachable yet: `502`, modelpipe's
        /// `tunnel_unavailable`.
        case refusing
        /// Nothing, until ``release(at:)`` or until the request is called off.
        case holding
    }

    static let listed = ["Qwen3.8-27B"]

    private static let answers = Mutex<[String: Answer]>([:])
    private static let modelsAsked = Mutex<[String: Int]>([:])
    private static let statusAsked = Mutex<[String: Int]>([:])
    private static let held = Mutex<[String: [ModelsServer]]>([:])

    static func answer(_ answer: Answer, at host: String) {
        answers.withLock { $0[host] = answer }
    }

    static func modelRequests(at host: String) -> Int {
        modelsAsked.withLock { $0[host] ?? 0 }
    }

    static func statusRequests(at host: String) -> Int {
        statusAsked.withLock { $0[host] ?? 0 }
    }

    /// Answers every held request at `host` with the model list, now.
    static func release(at host: String) {
        let waiting = held.withLock { held -> [ModelsServer] in
            defer { held[host] = [] }
            return held[host] ?? []
        }
        for server in waiting { server.list() }
    }

    static func provider(at host: String) -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelsServer.self]
        return OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, session: URLSession(configuration: configuration))
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        if url.path().hasSuffix("/proxy/status") {
            Self.statusAsked.withLock { $0[host, default: 0] += 1 }
            respond(200, body: "{}")
            return
        }
        Self.modelsAsked.withLock { $0[host, default: 0] += 1 }
        switch Self.answers.withLock({ $0[host] }) ?? .listing {
        case .listing:
            list()
        case .refusing:
            respond(
                502,
                body: #"{"error":{"code":"tunnel_unavailable","#
                    + #""message":"no tunnel to the serving side is connected right now"}}"#)
        case .holding:
            // Assigned rather than appended through the subscript, which
            // Swift 6's region check refuses; see `StatusServer`.
            Self.held.withLock { $0[host] = ($0[host] ?? []) + [self] }
        }
    }

    private func list() {
        let data = Self.listed.map { #"{"id":"\#($0)","object":"model"}"# }.joined(separator: ",")
        respond(200, body: #"{"object":"list","data":[\#(data)]}"#)
    }

    private func respond(_ status: Int, body: String) {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
