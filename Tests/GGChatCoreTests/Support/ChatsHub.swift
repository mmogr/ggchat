import Foundation
import Synchronization

@testable import GGChatCore

/// gglib's chats routes, served in process per host: each path under the
/// base URL answers as it was told to, and any other is a 404 with no body.
/// Each test uses its own host.
final class ChatsHub: URLProtocol, @unchecked Sendable {
    struct Answer: Sendable {
        var status = 200
        var body: String
        var type = "application/json"
    }

    private static let answers = Mutex<[String: [String: Answer]]>([:])
    private static let seen = Mutex<[String: [URLRequest]]>([:])

    /// Answers `path`, such as `/v1/chats/12`, at `host` with `answer`.
    static func serve(_ answer: Answer, at path: String, on host: String) {
        answers.withLock { $0[host, default: [:]][path] = answer }
    }

    static func requests(at host: String) -> [URLRequest] {
        seen.withLock { $0[host] ?? [] }
    }

    static func provider(at host: String) -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatsHub.self]
        return OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, apiKey: "hub-key",
            session: URLSession(configuration: configuration))
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        Self.seen.withLock { $0[host] = ($0[host] ?? []) + [request] }
        guard let answers = Self.answers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let answer = answers[url.path()] ?? Answer(status: 404, body: "", type: "text/plain")
        let response = HTTPURLResponse(
            url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": answer.type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
