import Foundation
import Synchronization
import XCTest

@testable import GGChatCore

final class PairingTests: XCTestCase {
    private let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"

    private var redeemer: HTTPPairingRedeemer {
        HTTPPairingRedeemer(session: StubURLProtocol.makeSession())
    }

    private func baseURL(_ host: String) -> URL {
        URL(string: "http://\(host)/v1")!
    }

    // MARK: - The exchange

    /// gglib's pairing route is outside the bearer group and checks the code
    /// against the one that session minted, while the tunnel edge admits the
    /// request only because the bearer *is* the code. Sending one half is
    /// refused exactly like sending neither, so both halves are asserted.
    func testTheCodeTravelsAsTheBearerAndInTheBody() async throws {
        let host = "pair-both.test"
        StubURLProtocol.register(
            host: host, path: "/v1/remote/pair",
            .init(status: 200, chunks: [Data(#"{"api_key":"far-machine-key"}"#.utf8)]))

        let key = try await redeemer.redeem(code: "483920", through: baseURL(host))

        XCTAssertEqual(key, "far-machine-key")
        let request = try XCTUnwrap(StubURLProtocol.requests(host: host).last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/v1/remote/pair", "gglib serves the route under /v1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer 483920")
        let body = try XCTUnwrap(Self.body(of: request))
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(sent, ["code": "483920"])
    }

    /// A first request may still be finishing a hole punch, so it is given
    /// room; a tunnel that never answers is a failure to report, not one to
    /// wait out. gglib's own redeem waits the same 20 seconds.
    func testTheExchangeIsGivenTwentySecondsAndNoMore() async throws {
        let host = "pair-timeout.test"
        StubURLProtocol.register(
            host: host, path: "/v1/remote/pair",
            .init(status: 200, chunks: [Data(#"{"api_key":"k"}"#.utf8)]))
        _ = try await redeemer.redeem(code: "483920", through: baseURL(host))
        let request = try XCTUnwrap(StubURLProtocol.requests(host: host).last)
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(HTTPPairingRedeemer.timeout, 20)
    }

    /// Wrong, expired, spent and burned are one flat 401 on the far side, so
    /// that a guesser learns nothing from which refusal they got. This side
    /// turns that one answer into one sentence naming all four.
    func testARefusedCodeBlamesTheCodeAndNotTheNetwork() async throws {
        let host = "pair-refused.test"
        StubURLProtocol.register(
            host: host, path: "/v1/remote/pair",
            .init(
                status: 401,
                chunks: [Data(#"{"error":{"message":"That pairing code was not accepted."}}"#.utf8)]))
        do {
            _ = try await redeemer.redeem(code: "000000", through: baseURL(host))
            XCTFail("a refused code produced a key")
        } catch let error as PairingError {
            XCTAssertEqual(error, .refused)
            let sentence = try XCTUnwrap(error.errorDescription)
            XCTAssertTrue(sentence.contains("expired"), sentence)
            XCTAssertTrue(sentence.contains("used already"), sentence)
            XCTAssertTrue(sentence.contains("gglib remote enable"), sentence)
        }
    }

    func testAnUnexpectedStatusAndAnUnreadableBodyAreToldApart() async throws {
        StubURLProtocol.register(
            host: "pair-500.test", path: "/v1/remote/pair",
            .init(status: 500, chunks: [Data("boom".utf8)]))
        StubURLProtocol.register(
            host: "pair-junk.test", path: "/v1/remote/pair",
            .init(status: 200, chunks: [Data(#"{"key":"wrong-name"}"#.utf8)]))

        do {
            _ = try await redeemer.redeem(code: "483920", through: baseURL("pair-500.test"))
            XCTFail("a 500 produced a key")
        } catch let error as PairingError {
            XCTAssertEqual(error, .unexpectedStatus(500))
        }
        do {
            _ = try await redeemer.redeem(code: "483920", through: baseURL("pair-junk.test"))
            XCTFail("a body with no api_key produced a key")
        } catch let error as PairingError {
            guard case .malformedResponse = error else { return XCTFail("\(error)") }
        }
    }

    /// Nothing is listening. The pipe itself is up — the request went to its
    /// own loopback port — so this is the far machine not answering, and the
    /// sentence must not send anyone back to look at their code.
    func testAnUnansweredRequestIsReportedAsSuchAndNotAsARefusal() async throws {
        do {
            _ = try await redeemer.redeem(code: "483920", through: baseURL("pair-silent.test"))
            XCTFail("an unanswered request produced a key")
        } catch let error as PairingError {
            guard case .unreachable = error else { return XCTFail("\(error)") }
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    // MARK: - The step before the seam

    /// The pairing step is built out of `PipeConnector` rather than added to
    /// it: dial with the ticket, redeem through the port that dial bound,
    /// hang up, and hand back a token the seam's own two parameters carry.
    func testPairingDialsRedeemsThroughThatPipeAndHangsUp() async throws {
        let connector = SpyPipeConnector()
        let far = RecordingRedeemer(.success("far-machine-key"))
        let key = try await PipePairing(connector: connector, redeemer: far)
            .token(ticket: ticket, code: "483920")

        XCTAssertEqual(key, "far-machine-key")
        XCTAssertEqual(connector.dialled, [ticket], "the ticket alone is what is dialled")
        XCTAssertEqual(far.calls.count, 1)
        let call = try XCTUnwrap(far.calls.first)
        XCTAssertEqual(call.code, "483920")
        XCTAssertEqual(
            call.baseURL, SpyPipeConnector.baseURL,
            "the code goes through the pipe it just opened, not over the open internet")
        XCTAssertEqual(connector.sessions.map(\.shutdowns), [1], "the pairing pipe is hung up")
    }

    /// A spent code must not leave a pipe up. There is nothing to retry
    /// through it: the next attempt starts on the other machine.
    func testTheSessionIsHungUpEvenWhenTheCodeIsRefused() async throws {
        let connector = SpyPipeConnector()
        let pairing = PipePairing(connector: connector, redeemer: RecordingRedeemer(.failure(.refused)))
        do {
            _ = try await pairing.token(ticket: ticket, code: "000000")
            XCTFail("a refused code produced a token")
        } catch let error as PairingError {
            XCTAssertEqual(error, .refused)
        }
        XCTAssertEqual(connector.sessions.map(\.shutdowns), [1], "the pairing pipe is hung up anyway")
    }

    func testEveryRefusalHasASentence() {
        let errors: [PairingError] = [
            .refused, .unreachable("no route"), .unexpectedStatus(503), .malformedResponse("x"),
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }

    /// `URLSession` hands `URLProtocol` a POST body as a stream rather than
    /// as `httpBody`, so both are read.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Counts its own shutdowns, so "the pairing pipe is hung up" is a number
/// rather than an inference from a stream that finished.
final class SpyPipeSession: PipeSession, Sendable {
    let baseURL: URL
    private let closed = Mutex(0)

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    var status: AsyncStream<PipeStatus> {
        AsyncStream<PipeStatus> { $0.finish() }
    }

    var shutdowns: Int {
        closed.withLock { $0 }
    }

    func shutdown() async {
        closed.withLock { $0 += 1 }
    }
}

/// Records what it was asked to dial and hands back a session that counts.
final class SpyPipeConnector: PipeConnector, Sendable {
    static let baseURL = URL(string: "http://127.0.0.1:52001/v1")!

    private let state = Mutex<(tickets: [String], sessions: [SpyPipeSession])>(([], []))

    var dialled: [String] {
        state.withLock { $0.tickets }
    }

    var sessions: [SpyPipeSession] {
        state.withLock { $0.sessions }
    }

    func connect(ticket: String, token: String) async throws -> any PipeSession {
        let session = SpyPipeSession(baseURL: Self.baseURL)
        state.withLock {
            $0.tickets.append(ticket)
            $0.sessions.append(session)
        }
        return session
    }
}

/// A redeemer with a fixed answer that remembers what it was asked.
final class RecordingRedeemer: PairingRedeemer, Sendable {
    struct Call: Sendable {
        var code: String
        var baseURL: URL
    }

    private let recorded = Mutex<[Call]>([])
    private let outcome: Result<String, PairingError>

    init(_ outcome: Result<String, PairingError>) {
        self.outcome = outcome
    }

    var calls: [Call] {
        recorded.withLock { $0 }
    }

    func redeem(code: String, through baseURL: URL) async throws -> String {
        recorded.withLock { $0.append(Call(code: code, baseURL: baseURL)) }
        return try outcome.get()
    }
}
