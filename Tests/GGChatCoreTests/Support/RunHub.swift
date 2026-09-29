import Foundation
import Synchronization

@testable import GGChatCore

/// gglib's runs routes, served in process per host. A run's events are the
/// data lines of a recorded chat stream, numbered from 1, then `event: run`
/// with the run's last report. Each test uses its own hosts.
final class RunHub: URLProtocol, @unchecked Sendable {
    struct Script: Sendable {
        /// The data of each event, in order; event `n` is `frames[n - 1]`.
        var frames: [String]
        /// The run's last report, sent as `event: run`.
        var ending: String
        /// The status and body a `PUT` is answered with.
        var put = (status: 201, body: "")
        /// Bytes of the next events body sent before the connection drops,
        /// once; nil sends it all.
        var cutAt: Int?
        /// Sends every event whatever `after` asked for.
        var ignoresAfter = false
        /// The status and body every events request is refused with.
        var refusal: (status: Int, body: String)?
    }

    private static let scripts = Mutex<[String: Script]>([:])
    private static let seen = Mutex<[String: [URLRequest]]>([:])

    static func serve(_ script: Script, at host: String) {
        scripts.withLock { $0[host] = script }
    }

    /// Drops the connection after `bytes` of the next events body.
    static func cut(at bytes: Int, at host: String) {
        scripts.withLock { $0[host]?.cutAt = bytes }
    }

    static func requests(at host: String) -> [URLRequest] {
        seen.withLock { $0[host] ?? [] }
    }

    static func provider(at host: String, log: any LogSink = NoopLogSink()) -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RunHub.self]
        return OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, apiKey: "hub-key",
            session: URLSession(configuration: configuration),
            log: log)
    }

    /// The whole events body for a read after `after`.
    static func eventsBody(_ script: Script, after: Int) -> Data {
        var text = ""
        for (index, frame) in script.frames.enumerated() where script.ignoresAfter || index + 1 > after {
            text += "id: \(index + 1)\ndata: \(frame)\n\n"
        }
        text += "event: run\ndata: \(script.ending)\n\n"
        return Data(text.utf8)
    }

    /// A run's last report, as gglib writes it.
    static func report(_ id: String, _ status: String, lastSeq: Int, error: String? = nil) -> String {
        let failure = error.map { #","error":{"code":"\#($0)","message":"it broke"}"# } ?? ""
        return #"{"id":"\#(id)","kind":"chat","status":"\#(status)","created_at_ms":1790000000000,"#
            + #""last_seq":\#(lastSeq)\#(failure)}"#
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        Self.seen.withLock { $0[host] = ($0[host] ?? []) + [request] }
        guard var script = Self.scripts.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let path = url.path()
        if request.httpMethod == "PUT" {
            respond(script.put.status, Data(script.put.body.utf8))
        } else if path.hasSuffix("/cancel") {
            respond(200, Data(script.ending.utf8))
        } else if let refusal = script.refusal {
            respond(refusal.status, Data(refusal.body.utf8))
        } else {
            let after =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "after" }?.value.flatMap(Int.init) ?? 0
            var body = Self.eventsBody(script, after: after)
            if let cut = script.cutAt {
                body = body.prefix(cut)
                script.cutAt = nil
                Self.scripts.withLock { $0[host] = script }
            }
            respond(200, body)
        }
    }

    private func respond(_ status: Int, _ body: Data) {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
