import Foundation
import GGChatCore
import XCTest

@testable import GGChatPipe

/// The connector as it ships, dialling a real `modelpipe serve` on this
/// machine, and a request carried through the pipe to the far edge and back.
///
/// Every other connector test drives a fake dial, and `BindingTests` dials
/// tickets that name nobody, so a release of the binding that could no longer
/// pair with a real serve would pass them all. This is the one place a ticket
/// a serve really printed is dialled, through `ModelpipeConnector.live`. Two
/// things differ from a shipped dial. The network is turned down: discovery,
/// port mapping and the public relays are off on both sides, as
/// ``ModelpipeServe`` says. And this device's key is kept in a scratch
/// directory rather than under Application Support, so a key really is kept
/// and dialled with, as the app keeps one, without touching the app's own.
///
/// What crosses the pipe is judged by what only the far edge can say. A
/// wrong bearer is refused `401` by serve, which checks the token before it
/// dials its backend; this side of a pipe forwards `Authorization` verbatim
/// and checks nothing. The right bearer is let through to a backend that is
/// not there, which serve answers `502` with the code `backend_unreachable`.
/// This side writes a `502` of its own when it has no pipe at all, with the
/// code `tunnel_unavailable`, so the status alone would pass with nothing
/// carried; the code is what tells the two apart.
///
/// Skipped without `MODELPIPE_BIN`, and failed instead with
/// `GGCHAT_PIPE_REQUIRED=1`, which `make test-pipe` sets.
final class RealPipeTests: XCTestCase {
    /// How long the pairing has to form once the local port is bound. On one
    /// machine it takes well under a second; the margin is for a loaded
    /// runner.
    private static let pairing: Duration = .seconds(20)

    func testADialledPipeCarriesARequestToTheFarEdgeAndItsAnswerBack() async throws {
        let serve = try await ModelpipeServe.start(requiring: "ggchat-real-pipe-\(UUID().uuidString)")
        addTeardownBlock { await serve.stop() }
        let keys = FileManager.default.temporaryDirectory.appending(path: "ggchat-real-pipe-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: keys) }
        let identities = PipeIdentityFiles(directory: keys)
        let connector = ModelpipeConnector.live(
            identities: identities,
            options: .init(discovery: false, portMapping: false, relayURL: ModelpipeServe.deadRelay))

        let session = try await connector.connect(ticket: serve.ticket, token: serve.token)
        addTeardownBlock { await session.shutdown() }
        XCTAssertEqual(session.baseURL.host(), "127.0.0.1")
        let directory = try XCTUnwrap(identities.directoryPath())
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory).count, 1,
            "the dial kept no key in \(directory)")
        let carrying = await Self.firstConnected(session.status, within: Self.pairing)
        _ = try XCTUnwrap(carrying, "the pipe did not reach \(serve.ticket) within \(Self.pairing)")

        let refused = try await Self.models(at: session.baseURL, bearer: "not-\(serve.token)")
        XCTAssertEqual(refused.status, 401, "a wrong bearer was not refused at the far edge: \(refused.body)")
        XCTAssertEqual(refused.code, "invalid_api_key", refused.body)

        let forwarded = try await Self.models(at: session.baseURL, bearer: serve.token)
        XCTAssertEqual(forwarded.status, 502, "the right bearer did not reach serve's backend: \(forwarded.body)")
        XCTAssertEqual(
            forwarded.code, "backend_unreachable",
            "a 502 that is not serve's own about its backend was not carried: \(forwarded.body)")
    }

    /// The first status that says requests can reach the far side, or `nil`
    /// when none arrives in time.
    private static func firstConnected(
        _ statuses: AsyncStream<PipeStatus>, within limit: Duration
    ) async -> PipeStatus? {
        await withTaskGroup(of: PipeStatus?.self) { group in
            group.addTask {
                for await status in statuses where status.isConnected { return status }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
    }

    /// What one request for the model list was answered with.
    private struct Answer {
        let status: Int
        let body: String
        /// The `error.code` of modelpipe's own refusals.
        let code: String?
    }

    private struct Refusal: Decodable {
        struct Detail: Decodable { let code: String? }
        let error: Detail
    }

    private static func models(at baseURL: URL, bearer: String) async throws -> Answer {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        let status = try XCTUnwrap(response as? HTTPURLResponse).statusCode
        let code = (try? JSONDecoder().decode(Refusal.self, from: data))?.error.code
        return Answer(status: status, body: String(decoding: data, as: UTF8.self), code: code)
    }
}
