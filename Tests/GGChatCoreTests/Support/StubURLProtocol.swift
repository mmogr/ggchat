import Foundation
import Synchronization

/// Serves canned HTTP responses keyed by host and path, so provider tests
/// never touch the network. Each test uses its own host.
///
/// A stub sends its response, every chunk and the finish inside
/// `startLoading`, unless it is held: then the response goes at once and
/// each chunk waits for the test to release it, so the reader suspends
/// between chunks as it does on a network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status: Int
        var headers: [String: String] = ["Content-Type": "application/json"]
        var chunks: [Data]
        /// Sends each chunk only when `release(host:)` lets it through, and
        /// finishes with the last. A request that is stopped is sent nothing
        /// more.
        var held = false
    }

    /// How far the held answer at one host has been let through.
    private struct Hold {
        var released = 0
        var stops = 0
        /// The load sending it, until it finishes or is stopped.
        var load: StubURLProtocol?
    }

    /// A held answer being sent: its host, its chunks and how many have gone.
    private struct Sending {
        var host: String
        var chunks: [Data]
        var sent = 0
    }

    private static let stubs = Mutex<[String: [String: Stub]]>([:])
    private static let seen = Mutex<[URLRequest]>([])
    private static let holds = Mutex<[String: Hold]>([:])
    /// The held answer this load is sending, until it finishes or is stopped.
    private let sending = Mutex<Sending?>(nil)
    /// The run loop of the thread that started this load, which is where a
    /// held answer is sent and where `stopLoading` is called.
    private var loop: CFRunLoop?

    /// Serves `stub` at `path` on `host`. A held stub starts with nothing
    /// released and no stops counted at `host`.
    static func register(host: String, path: String, _ stub: Stub) {
        stubs.withLock { $0[host, default: [:]][path] = stub }
        if stub.held { holds.withLock { $0[host] = Hold() } }
    }

    static func requests(host: String) -> [URLRequest] {
        seen.withLock { $0.filter { $0.url?.host() == host } }
    }

    /// Lets the next chunk of the held answer at `host` through, and its
    /// finish with the last. A release before the request has started is
    /// kept for it.
    static func release(host: String) {
        let load = holds.withLock { holds in
            holds[host, default: Hold()].released += 1
            return holds[host]?.load
        }
        load?.sendReleasedOnItsThread()
    }

    /// How many held answers at `host` had their request stopped before
    /// they finished.
    static func stopped(host: String) -> Int {
        holds.withLock { $0[host]?.stops ?? 0 }
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
        if stub.held {
            loop = CFRunLoopGetCurrent()
            sending.withLock { $0 = Sending(host: host, chunks: stub.chunks) }
            Self.holds.withLock { $0[host, default: Hold()].load = self }
            sendReleased()
            return
        }
        for chunk in stub.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Counts a held answer stopped before it finished. URLSession calls
    /// this after every load, a finished one too, and that is not a stop.
    override func stopLoading() {
        guard let host = sending.withLock({ $0.take()?.host }) else { return }
        Self.holds.withLock {
            $0[host]?.stops += 1
            $0[host]?.load = nil
        }
    }

    /// Sends what has been released on the thread that started the load,
    /// so a send and a stop never overlap.
    private func sendReleasedOnItsThread() {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { self.sendReleased() }
        CFRunLoopWakeUp(loop)
    }

    /// Sends each chunk released and not yet sent, then the finish in the
    /// same pass as the last chunk, before a stop can come between them. A
    /// load that was stopped or has finished sends nothing.
    private func sendReleased() {
        while let next = nextReleased() {
            if let chunk = next {
                client?.urlProtocol(self, didLoad: chunk)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    /// The next released chunk, `.some(nil)` for the finish once every chunk
    /// has gone, or nil when nothing released is left to send.
    private func nextReleased() -> Data?? {
        guard let host = sending.withLock({ $0?.host }) else { return nil }
        let released = Self.holds.withLock { $0[host]?.released ?? 0 }
        let next = sending.withLock { sending -> Data?? in
            guard let current = sending, current.sent < released || current.sent == current.chunks.count
            else { return nil }
            guard current.sent < current.chunks.count else {
                sending = nil
                return .some(nil)
            }
            sending?.sent += 1
            return .some(current.chunks[current.sent])
        }
        if case .some(nil) = next { Self.holds.withLock { $0[host]?.load = nil } }
        return next
    }
}
