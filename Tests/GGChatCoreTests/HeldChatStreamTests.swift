import XCTest

@testable import GGChatCore

/// A chat reply read through URLSession from an answer that comes a chunk at
/// a time, each released by the test, so the reader suspends between chunks
/// and can be stopped while it waits.
final class HeldChatStreamTests: XCTestCase {
    private let request = ChatRequest(
        model: "Qwen3.8-27B", messages: [Message(role: .user, content: "hi", createdAt: .distantPast)])

    private func frame(_ text: String) -> String {
        #"data: {"choices":[{"delta":{"content":"\#(text)"},"index":0}]}"# + "\n\n"
    }

    /// A provider at `host` whose chat answer is held, in these chunks.
    private func held(
        _ chunks: [String], host: String, log: any LogSink = NoopLogSink()
    ) -> OpenAICompatibleProvider {
        StubURLProtocol.register(
            host: host, path: "/v1/chat/completions",
            .init(
                status: 200, headers: ["Content-Type": "text/event-stream"], chunks: chunks.map { Data($0.utf8) },
                held: true))
        return OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, apiKey: nil, session: StubURLProtocol.makeSession(), log: log)
    }

    /// Reads the reply from a provider at `host` held in these chunks, in a
    /// task of its own that hands back every event it was passed once it
    /// ends; `arrivals` has each event as it comes. Only the reading holds
    /// the provider, so `log` goes when the provider's own reading has ended.
    private func reader(
        of chunks: [String], host: String, log: any LogSink = NoopLogSink()
    ) -> (task: Task<[ChatEvent], Never>, arrivals: AsyncStream<ChatEvent>) {
        let (arrivals, arrived) = AsyncStream.makeStream(of: ChatEvent.self)
        let provider = held(chunks, host: host, log: log)
        let request = request
        let task = Task {
            var seen: [ChatEvent] = []
            for await event in provider.stream(request) {
                seen.append(event)
                arrived.yield(event)
            }
            arrived.finish()
            return seen
        }
        return (task, arrivals)
    }

    /// Waits, a bounded while, for the request at `host` to be stopped, as a
    /// stop reaches the stub on URLSession's own thread.
    private func stops(at host: String) async throws -> Int {
        for _ in 0..<200 where StubURLProtocol.stopped(host: host) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        return StubURLProtocol.stopped(host: host)
    }

    /// A chunk that comes after the reader has waited for it, holding half an
    /// event, is passed on after the ones before it, the event read whole,
    /// and the reply finishes when the answer does.
    func testAChunkThatComesAfterTheReaderWaitedIsPassedOnAfterTheOnesBefore() async {
        let host = "held-order.test"
        let two = frame("two")
        let provider = held(
            [frame("one ") + String(two.prefix(20)), String(two.dropFirst(20)), "data: [DONE]\n\n"], host: host)
        var events = provider.stream(request).makeAsyncIterator()
        StubURLProtocol.release(host: host)
        let first = await events.next()
        XCTAssertEqual(first, .delta("one "))
        StubURLProtocol.release(host: host)
        let second = await events.next()
        XCTAssertEqual(second, .delta("two"), "half an event was lost while the reader waited for the rest")
        StubURLProtocol.release(host: host)
        let ending = await events.next()
        XCTAssertEqual(ending, .finished(reason: nil, usage: nil))
        let after = await events.next()
        XCTAssertNil(after)
        XCTAssertEqual(StubURLProtocol.stopped(host: host), 0, "an answer that finished was counted as stopped")
    }

    /// Cancelling the reader while half an event has come reaches the
    /// request: it is stopped once, and it is the only request made.
    func testCancellingTheReaderMidEventStopsTheRequestOnce() async throws {
        let host = "held-cancel.test"
        let two = frame("two")
        let (task, arrivals) = reader(
            of: [frame("one ") + String(two.prefix(20)), String(two.dropFirst(20))], host: host)
        StubURLProtocol.release(host: host)
        var arrived = arrivals.makeAsyncIterator()
        let first = await arrived.next()
        XCTAssertEqual(first, .delta("one "))
        task.cancel()
        let seen = await task.value
        XCTAssertEqual(seen, [.delta("one ")])
        let stopped = try await stops(at: host)
        XCTAssertEqual(stopped, 1, "the request outlived its reader")
        XCTAssertEqual(StubURLProtocol.requests(host: host).count, 1)
    }

    /// Stop between two chunks, as the app's Stop cancels its reading task,
    /// stops the request once, and the provider's reading ends without
    /// logging an error.
    func testAStopBetweenChunksStopsTheRequestAndLogsNoError() async throws {
        let host = "held-stop.test"
        let lines = CapturingLogSink()
        let ended = expectation(description: "the provider's reading ended")
        let (task, arrivals) = reader(
            of: [frame("one "), frame("two"), "data: [DONE]\n\n"], host: host,
            log: EndingSink(forwardingTo: lines, ended: ended))
        StubURLProtocol.release(host: host)
        var arrived = arrivals.makeAsyncIterator()
        let first = await arrived.next()
        XCTAssertEqual(first, .delta("one "))
        task.cancel()
        let seen = await task.value
        XCTAssertEqual(seen, [.delta("one ")])
        let stopped = try await stops(at: host)
        XCTAssertEqual(stopped, 1, "the request outlived its reader")
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(lines.lines.filter { $0.hasPrefix("[error]") }, [], "a stop was logged as the stream failing")
    }
}

/// Passes each line on, and says when it goes: held by a provider alone, it
/// goes when the provider does, once nothing of the provider's is running.
private final class EndingSink: LogSink, Sendable {
    private let lines: CapturingLogSink
    private let ended: XCTestExpectation

    init(forwardingTo lines: CapturingLogSink, ended: XCTestExpectation) {
        self.lines = lines
        self.ended = ended
    }

    deinit { ended.fulfill() }

    func log(_ level: LogLevel, _ message: String) { lines.log(level, message) }
}
