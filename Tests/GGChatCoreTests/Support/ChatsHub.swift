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
        /// Sent in place of `body` when set: an image's bytes.
        var bytes: Data?
        /// Whether a URL cache may keep the answer, and is told it may for
        /// an hour.
        var cacheable = false
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

    /// A provider for `host` whose session reads through this hub, and
    /// keeps answers in `cache` when one is given.
    static func provider(at host: String, cache: URLCache? = nil) -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatsHub.self]
        if let cache { configuration.urlCache = cache }
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
        var headers = ["Content-Type": answer.type]
        if answer.cacheable { headers["Cache-Control"] = "max-age=3600" }
        let response = HTTPURLResponse(
            url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: answer.cacheable ? .allowed : .notAllowed)
        client?.urlProtocol(self, didLoad: answer.bytes ?? Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
