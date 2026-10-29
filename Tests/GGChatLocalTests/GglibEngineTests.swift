import Foundation
import GGChatCore
import GGLib
import XCTest

@testable import GGChatLocal

/// gglib's engine behind the app's seam, over fakes of the binding's
/// library, server and watch: a refusal said as the app's, the reading that
/// crosses, the stream a watch drives and how it ends, the shutdown, and the
/// library's own open served from.
final class GglibEngineTests: XCTestCase {
    private let reading = GGChatCore.DeviceReading(
        physicalBytes: 8 << 30, availableBytes: 5 << 30, isSimulator: false)

    private func engine(_ library: FakeLibrary) -> GglibEngine {
        GglibEngine(isAvailable: true) { library }
    }

    /// Everything a stream says until it finishes.
    private static func collect(_ stream: AsyncStream<EngineStatus>) async -> [EngineStatus] {
        var said: [EngineStatus] = []
        for await status in stream { said.append(status) }
        return said
    }

    /// Waits, for up to `limit`, until `done` holds, and answers whether it
    /// did, for `AppModelEngineTests.waitUntil`'s reason.
    private func waitUntil(within limit: Duration = .seconds(10), _ done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !done(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(1)) }
        return done()
    }

    /// A serve gglib refuses is refused with the app's error, so its
    /// sentence is the app's; and the reading crossed field for field.
    func testAServeGglibRefusesIsTheAppsErrorAndTheReadingCrossedAsRead() async {
        let library = FakeLibrary(serving: { throw GglibError.DoesNotFit(need: 6 << 30, have: 3 << 30) })
        do {
            _ = try await engine(library).serve(reading: reading)
            XCTFail("a refused serve served")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .doesNotFit(need: 6 << 30, have: 3 << 30))
        }
        XCTAssertEqual(
            library.said.readings,
            [GGLib.DeviceReading(physicalBytes: 8 << 30, availableBytes: 5 << 30, isSimulator: false)])
    }

    /// The session is at the server's loopback address with its key.
    func testTheSessionIsAtTheServersAddressWithItsKey() async throws {
        let session = try await engine(FakeLibrary(serving: { FakeServer.make() })).serve(reading: reading)
        XCTAssertEqual(session.baseURL, URL(string: "http://127.0.0.1:49170/v1"))
        XCTAssertEqual(session.apiKey, "fake-engine-key")
    }

    /// A server somewhere other than this device's loopback is shut down,
    /// and the serve refused: no request is sent off the device in the clear.
    func testAServerOffLoopbackIsShutDownAndRefused() async {
        let server = FakeServer.make(baseUrl: "http://192.168.1.4:49170/v1")
        do {
            _ = try await engine(FakeLibrary(serving: { server })).serve(reading: reading)
            XCTFail("a server off loopback was kept")
        } catch {
            XCTAssertNotNil(error as? OnDeviceError, "\(error)")
        }
        XCTAssertEqual(server.shutdowns, 1)
        XCTAssertNil(GglibEngine.loopback("http://localhost:1/v1"), "a name was taken for the loopback address")
        XCTAssertNil(GglibEngine.loopback("http://127.0.0.1/v1"), "an address with no port was taken")
        XCTAssertNotNil(GglibEngine.loopback("http://127.0.0.1:1/v1"))
    }

    /// The stream says where the engine stands first, then each change: a
    /// load to ready carries the model's name and its context; the shutdown
    /// ends it on stopped, and it finishes.
    func testTheStreamWalksFromWhereTheEngineStandsAndFinishesAfterStopped() async throws {
        let server = FakeServer.make()
        let session = try await engine(FakeLibrary(serving: { server })).serve(reading: reading)
        server.move(to: .loading(model: "tinygemma3", fraction: 0.5))
        // The stream is taken out here: Xcode 26.6's region checker cannot
        // follow the session into the task, and a stream is Sendable.
        let status = session.status
        let following = Task { await Self.collect(status) }
        let first = await waitUntil { server.pulls >= 2 }
        XCTAssertTrue(first, "the stream never asked past where the engine stood")
        server.move(to: .ready(model: "tinygemma3", nCtx: 4_096))
        let readied = await waitUntil { server.pulls >= 3 }
        XCTAssertTrue(readied, "the stream never asked past ready")
        await session.shutdown()

        let said = await following.value
        XCTAssertEqual(
            said,
            [.loading(model: "tinygemma3", fraction: 0.5), .ready(model: "tinygemma3", nCtx: 4_096), .stopped])
    }

    /// A consumer that stops listening stops the pulling: the step already
    /// asked for ends at the engine's next change, and nothing is asked
    /// after it.
    func testAConsumerThatStopsListeningStopsThePulling() async throws {
        let server = FakeServer.make()
        let session = try await engine(FakeLibrary(serving: { server })).serve(reading: reading)
        let following = Task {
            for await _ in session.status {}
        }
        let waiting = await waitUntil { server.pulls >= 2 }
        XCTAssertTrue(waiting, "the stream never asked past idle")
        following.cancel()
        await following.value
        server.move(to: .loading(model: "tinygemma3", fraction: 0.1))
        server.move(to: .ready(model: "tinygemma3", nCtx: 2_048))
        for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(server.pulls, 2, "a stream nobody listens to went on asking")
    }

    /// Shutting down twice is shutting down: each returns, and a stream
    /// begun after says stopped and finishes.
    func testShuttingDownTwiceIsShuttingDown() async throws {
        let server = FakeServer.make()
        let session = try await engine(FakeLibrary(serving: { server })).serve(reading: reading)
        let status = session.status
        let following = Task { await Self.collect(status) }
        await session.shutdown()
        await session.shutdown()

        let said = await following.value
        XCTAssertEqual(said.last, .stopped)
        XCTAssertEqual(said.filter { $0 == .stopped }.count, 1, "a watch said stopped twice: \(said)")
        let after = await Self.collect(session.status)
        XCTAssertEqual(after, [.stopped], "a stream begun after the shutdown said \(after)")
    }

    /// The engine is served from the model library's own handle: an open
    /// that failed under a serve is not kept, the library's next question
    /// opens it again, and the serves after are served from that one.
    func testTheEngineIsServedFromTheLibrarysOwnOpen() async throws {
        let fake = FakeLibrary(serving: { FakeServer.make() })
        let opener = Opener([.failure(.Internal(message: "the database is locked")), .success(fake)])
        let library = GglibLibrary(open: { try opener.open() })
        let engine = GglibEngine(library: library)
        do {
            _ = try await engine.serve(reading: reading)
            XCTFail("a library that did not open served")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .internal(message: "the database is locked"))
        }
        _ = try await library.installed()
        _ = try await engine.serve(reading: reading)
        _ = try await engine.serve(reading: reading)
        XCTAssertEqual(opener.opens, 2, "the engine and the library did not share one open")
        XCTAssertEqual(fake.said.readings.count, 2)
    }

    /// gglib's engine runs on an iPhone and nowhere this package's tests
    /// run: the Mac offers nothing on-device.
    func testTheEngineIsOfferedOnlyOnADevice() {
        XCTAssertFalse(GglibEngine.runsHere)
        XCTAssertFalse(GglibEngine { FakeLibrary() }.isAvailable)
        XCTAssertFalse(GglibEngine(library: GglibLibrary(open: { FakeLibrary() })).isAvailable)
    }
}
