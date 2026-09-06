import XCTest

@testable import GGChatCore

final class MockPipeTests: XCTestCase {
    private let ticket = "pipeabcdefghijklmnop"

    func testStatusWalksIdleRelayedDirectThenClosedOnDemand() async throws {
        let sleeper = GatedSleeper()
        let connector = MockPipeConnector(sleeper: sleeper, registry: LoopbackProviderRegistry())
        let session = try await connector.connect(ticket: ticket, token: "token")
        var iterator = session.status.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first, .idle)
        await sleeper.release()
        let second = await iterator.next()
        XCTAssertEqual(second, .relayed)
        await sleeper.release()
        let third = await iterator.next()
        XCTAssertEqual(third, .direct)

        let mock = try XCTUnwrap(session as? MockPipeSession)
        mock.forceClosed()
        let fourth = await iterator.next()
        XCTAssertEqual(fourth, .closed)

        var late = session.status.makeAsyncIterator()
        let lateFirst = await late.next()
        XCTAssertEqual(lateFirst, .closed, "a late subscriber gets the current value first")

        await session.shutdown()
        let afterShutdown = await iterator.next()
        XCTAssertEqual(afterShutdown, .closed)
        let end = await iterator.next()
        XCTAssertNil(end, "shutdown ends the stream")
    }

    func testBaseURLIsLoopbackAndBoundToTheMockProvider() async throws {
        let registry = LoopbackProviderRegistry()
        let connector = MockPipeConnector(registry: registry)
        let session = try await connector.connect(ticket: ticket, token: "token")
        XCTAssertEqual(session.baseURL.host(), "127.0.0.1")
        XCTAssertEqual(session.baseURL.path(), "/v1")
        XCTAssertNotNil(registry.provider(for: session.baseURL))
        let provider = registry.makeProvider(baseURL: session.baseURL, apiKey: "token")
        XCTAssertTrue(provider is MockProvider)
        await session.shutdown()
        XCTAssertNil(registry.provider(for: session.baseURL))
        let real = registry.makeProvider(baseURL: URL(string: "http://127.0.0.1:8080/v1")!, apiKey: nil)
        XCTAssertTrue(real is OpenAICompatibleProvider)
    }

    func testAFixedURLCanBeRegisteredAndReplaced() {
        let registry = LoopbackProviderRegistry()
        let url = URL(string: "http://127.0.0.1:49151/v1")!
        registry.register(MockProvider(scripts: [.init(text: "one")]), at: url)
        registry.register(MockProvider(scripts: [.init(text: "two")]), at: url)
        XCTAssertEqual((registry.provider(for: url) as? MockProvider)?.scripts.first?.text, "two")
    }

    func testTwoSessionsGetDifferentPorts() async throws {
        let connector = MockPipeConnector(registry: LoopbackProviderRegistry())
        let one = try await connector.connect(ticket: ticket, token: "t")
        let two = try await connector.connect(ticket: ticket, token: "t")
        XCTAssertNotEqual(one.baseURL, two.baseURL)
    }

    func testBadTicketOrMissingTokenIsRefused() async {
        let connector = MockPipeConnector(registry: LoopbackProviderRegistry())
        do {
            _ = try await connector.connect(ticket: "nope", token: "t")
            XCTFail("expected a refusal")
        } catch let error as PipeConnectError {
            XCTAssertEqual(error, .invalidTicket(.badPrefix))
        } catch {
            XCTFail("\(error)")
        }
        do {
            _ = try await connector.connect(ticket: ticket, token: " ")
            XCTFail("expected a refusal")
        } catch let error as PipeConnectError {
            XCTAssertEqual(error, .missingToken)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testRelayDeliversCurrentValueFirstToEverySubscriber() async {
        let relay = PipeStatusRelay(initial: .relayed)
        var a = relay.stream().makeAsyncIterator()
        let aFirst = await a.next()
        XCTAssertEqual(aFirst, .relayed)
        relay.send(.direct)
        var b = relay.stream().makeAsyncIterator()
        let bFirst = await b.next()
        XCTAssertEqual(bFirst, .direct)
        let aSecond = await a.next()
        XCTAssertEqual(aSecond, .direct)
        relay.finish()
        let aEnd = await a.next()
        XCTAssertNil(aEnd)
        var c = relay.stream().makeAsyncIterator()
        let cFirst = await c.next()
        XCTAssertEqual(cFirst, .direct)
        let cEnd = await c.next()
        XCTAssertNil(cEnd)
    }
}
