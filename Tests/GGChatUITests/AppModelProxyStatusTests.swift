import GGChatCore
import Synchronization
import XCTest

@testable import GGChatUI

/// The far side of a mock pipe: answers `GET /v1/proxy/status` with the
/// statuses it is given, one per request, and holds a request it has no
/// status left for until the request is cancelled. Each test uses its own
/// host.
///
/// A mock pipe hands out whatever provider it was built with, so an
/// `OpenAICompatibleProvider` over this is a pipe whose far machine is gglib.
private final class StatusServer: URLProtocol, @unchecked Sendable {
    private static let answers = Mutex<[String: [Int]]>([:])
    private static let asked = Mutex<[String: Int]>([:])
    private static let held = Mutex<[String: [StatusServer]]>([:])

    static func answer(_ statuses: [Int], at host: String) {
        answers.withLock { $0[host] = statuses }
    }

    static func requests(at host: String) -> Int {
        asked.withLock { $0[host] ?? 0 }
    }

    /// Answers every request `startLoading` held at `host` for want of a
    /// status, with `status`, now.
    static func release(at host: String, with status: Int) {
        let waiting = held.withLock { held -> [StatusServer] in
            defer { held[host] = [] }
            return held[host] ?? []
        }
        for server in waiting { server.answer(status) }
    }

    static func provider(at host: String) -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusServer.self]
        return OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, session: URLSession(configuration: configuration))
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        Self.asked.withLock { $0[host, default: 0] += 1 }
        let status = Self.answers.withLock { answers -> Int? in
            guard var queue = answers[host], !queue.isEmpty else { return nil }
            defer { answers[host] = queue }
            return queue.removeFirst()
        }
        guard let status else {
            // Not `append(self)` on the subscript: Swift 6's region check
            // refuses that ("'inout sending' parameter '$0' cannot be
            // task-isolated"); assigning a new array is accepted.
            Self.held.withLock { $0[host] = ($0[host] ?? []) + [self] }
            return
        }
        answer(status)
    }

    private func answer(_ status: Int) {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// When the app asks whether a provider has a status pane. It asks as a
/// conversation opens, which for a pipe can be before the dial has returned.
final class AppModelProxyStatusTests: XCTestCase {
    /// modelpipe's normative vector 1, the shortest string that is a ticket.
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    @MainActor
    private func makeModel(
        answeringAt host: String, sleeper: any Sleeper = ImmediateSleeper()
    ) throws
        -> (AppModel, ProviderConfig)
    {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(
            sleeper: sleeper, provider: StatusServer.provider(at: host), registry: registry)
        let defaults = UserDefaults(suiteName: "AppModelProxyStatusTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: connector, diagnostics: Diagnostics(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let config = ProviderConfig(
            name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)), defaultModel: "mock-27b")
        try model.addProvider(config, credentials: [.ticket: ticket, .token: "secret-token"])
        return (model, config)
    }

    @MainActor
    private func waitForStatus(_ wanted: PipeStatus, _ model: AppModel, _ id: UUID) async {
        for _ in 0..<200 where model.pipeStatus(for: id) != wanted {
            await Task.yield()
        }
    }

    /// The probe as a pipe conversation opens on a launch, before the
    /// dial has returned. Asked through `makeProvider`, it raises
    /// "home is not connected yet." over a pill about to read Direct, and
    /// keeps "no pane" for a machine that has one.
    @MainActor
    func testProbingAPipeWithNoSessionRaisesNothingAndCachesNothing() async throws {
        let host = "no-session.status.test"
        StatusServer.answer([200], at: host)
        let (model, config) = try makeModel(answeringAt: host)

        await model.probeProxyStatus(for: config)

        XCTAssertNil(model.lastError, "a probe nobody asked for raised an alert")
        XCTAssertNil(model.proxyStatusAvailability[config.id], "an answer was kept for a pipe that was never asked")
        XCTAssertEqual(StatusServer.requests(at: host), 0)

        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        await model.probeProxyStatus(for: config)
        XCTAssertTrue(model.proxyStatusAvailable(for: config.id), "the pane stayed hidden once the pipe was up")
    }

    /// A session is installed before its far machine answers: `connect`
    /// returns once the local port is bound, and the tunnel's own edge
    /// answers `502` in that gap. What a probe finds there is forgotten when
    /// the pipe comes up, so the next probe, on the pulse, asks.
    @MainActor
    func testTheStatusPaneIsAskedForAgainWhenThePipeConnects() async throws {
        let host = "not-answering-yet.status.test"
        StatusServer.answer([502, 200], at: host)
        let sleeper = HeldSleeper()
        defer { sleeper.release() }
        let (model, config) = try makeModel(answeringAt: host, sleeper: sleeper)

        await model.connectPipe(for: config)
        XCTAssertEqual(model.pipeStatus(for: config.id), .idle)
        await model.probeProxyStatus(for: config)
        XCTAssertFalse(model.proxyStatusAvailable(for: config.id), "the far machine had not answered yet")

        sleeper.release()
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(
            model.connectedPulse, 1, "the connected pulse did not move on, so nothing would probe again")
        await model.probeProxyStatus(for: config)

        XCTAssertEqual(StatusServer.requests(at: host), 2, "the pipe came up and nobody asked again")
        XCTAssertTrue(model.proxyStatusAvailable(for: config.id))
    }

    /// A probe can be called off before its answer arrives, and a new one
    /// asked. The request then fails because it was called off, not because the
    /// server has no pane; kept, that answer would hide the pane until the
    /// next reconnect whenever the old probe finished after the new one began.
    @MainActor
    func testAProbeCalledOffBeforeItsAnswerKeepsNothing() async throws {
        let host = "called-off.status.test"
        let (model, config) = try makeModel(answeringAt: host)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)

        let probe = Task { await model.probeProxyStatus(for: config) }
        for _ in 0..<5_000 where StatusServer.requests(at: host) == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(StatusServer.requests(at: host), 1, "the probe never reached the server")
        probe.cancel()
        await probe.value

        XCTAssertNil(model.proxyStatusAvailability[config.id], "a probe that was called off kept an answer")
        StatusServer.answer([200], at: host)
        await model.probeProxyStatus(for: config)
        XCTAssertTrue(model.proxyStatusAvailable(for: config.id))
    }

    /// The other way a stale answer used to be kept: the request is answered
    /// after the pipe has come up again, and the old probe's cancellation is
    /// delivered late or not at all, since its answer was already in.
    /// `Task.isCancelled` cannot see that. The probe generation can, because a
    /// pipe coming up moves it on whether or not anything was cancelled.
    @MainActor
    func testAnAnswerThatArrivesAfterThePipeReconnectedIsNotKept() async throws {
        let host = "reconnected.status.test"
        let (model, config) = try makeModel(answeringAt: host)
        await model.connectPipe(for: config)
        await waitForStatus(.direct, model, config.id)

        let probe = Task { await model.probeProxyStatus(for: config) }
        for _ in 0..<5_000 where StatusServer.requests(at: host) == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(StatusServer.requests(at: host), 1, "the probe never reached the server")

        // The pipe goes down and is dialled again while the request is held —
        // through `reconnectPipe`, the pill's own path, so the connected pulse
        // and the generation move the way they do in the app — and the server
        // then answers the old request, unasked. A `forceClosed()` leaves the
        // mock's status stream open, so the dead session stays installed and
        // a bare `connectPipe` would refuse; the reconnect shuts it down first.
        let session = try XCTUnwrap(model.pipeSession(for: config.id) as? MockPipeSession)
        session.forceClosed()
        await waitForStatus(.closed, model, config.id)
        await model.reconnectPipe(for: config)
        await waitForStatus(.direct, model, config.id)
        XCTAssertEqual(model.connectedPulse, 2, "the pipe did not come up a second time")
        StatusServer.release(at: host, with: 200)
        await probe.value

        XCTAssertNil(model.proxyStatusAvailability[config.id], "an answer from before the reconnect was kept")
        StatusServer.answer([200], at: host)
        await model.probeProxyStatus(for: config)
        XCTAssertTrue(model.proxyStatusAvailable(for: config.id), "and the fresh probe after it did not get through")
    }
}
