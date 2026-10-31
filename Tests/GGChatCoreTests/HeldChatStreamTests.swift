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

    /// Reads the reply in a task of its own, which hands back every event it
    /// was passed once it ends; `arrivals` has each event as it comes.
    private func reader(
        of provider: OpenAICompatibleProvider
    ) -> (task: Task<[ChatEvent], Never>, arrivals: AsyncStream<ChatEvent>) {
        let (arrivals, arrived) = AsyncStream.makeStream(of: ChatEvent.self)
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

    /// A chunk that comes after the reader has waited for it is passed on
    /// after the ones before it, an event split across two chunks is read
    /// whole, and the reply finishes when the answer does.
    func testAChunkThatComesAfterTheReaderWaitedIsPassedOnAfterTheOnesBefore() async {
        let host = "held-order.test"
        let two = frame("two")
        let provider = held(
            [frame("one "), String(two.prefix(20)), String(two.dropFirst(20)), "data: [DONE]\n\n"], host: host)
        var events = provider.stream(request).makeAsyncIterator()
        StubURLProtocol.release(host: host)
        let first = await events.next()
        XCTAssertEqual(first, .delta("one "))
        StubURLProtocol.release(host: host)
        StubURLProtocol.release(host: host)
        let second = await events.next()
        XCTAssertEqual(second, .delta("two"), "half an event did not wait for its other half")
        StubURLProtocol.release(host: host)
        StubURLProtocol.release(host: host)
        let ending = await events.next()
        XCTAssertEqual(ending, .finished(reason: nil, usage: nil))
        let after = await events.next()
        XCTAssertNil(after)
        XCTAssertEqual(StubURLProtocol.stopped(host: host), 0, "an answer that finished was counted as stopped")
    }

    /// Cancelling the reader while half an event has come stops the request
    /// once, and nothing is passed on after the cancel: not the rest of the
    /// event, nor the reply's ending.
    func testCancellingTheReaderMidStreamStopsTheRequestOnceAndPassesNothingAfter() async throws {
        let host = "held-cancel.test"
        let two = frame("two")
        let provider = held([frame("one ") + String(two.prefix(20)), String(two.dropFirst(20))], host: host)
        let (task, arrivals) = reader(of: provider)
        StubURLProtocol.release(host: host)
        var arrived = arrivals.makeAsyncIterator()
        let first = await arrived.next()
        XCTAssertEqual(first, .delta("one "))
        task.cancel()
        let seen = await task.value
        XCTAssertEqual(seen, [.delta("one ")], "an event was passed on after the cancel")
        let stopped = try await stops(at: host)
        XCTAssertEqual(stopped, 1, "the request outlived its reader")
        XCTAssertEqual(StubURLProtocol.requests(host: host).count, 1)
    }

    /// Stop between two chunks, as the app's Stop cancels its reading task,
    /// ends the reply's stream with what came before it and no error: none
    /// is passed on, and none is logged.
    func testAStopBetweenChunksEndsTheStreamWithoutAnError() async throws {
        let host = "held-stop.test"
        let log = CapturingLogSink()
        let provider = held([frame("one "), frame("two"), "data: [DONE]\n\n"], host: host, log: log)
        let (task, arrivals) = reader(of: provider)
        StubURLProtocol.release(host: host)
        var arrived = arrivals.makeAsyncIterator()
        let first = await arrived.next()
        XCTAssertEqual(first, .delta("one "))
        task.cancel()
        let seen = await task.value
        XCTAssertEqual(seen, [.delta("one ")])
        let stopped = try await stops(at: host)
        XCTAssertEqual(stopped, 1, "the request outlived its reader")
        XCTAssertEqual(
            log.lines.filter { $0.hasPrefix("[error]") }, [], "a stop was logged as the stream failing")
    }
}
