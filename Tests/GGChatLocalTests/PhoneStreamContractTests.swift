import Foundation
import GGChatCore
import XCTest

/// Replays a reply gglib's engine streamed through its proxy, recorded on
/// the Mac's slice (`Fixtures/phone-stream.txt` says how), through the
/// ordinary `OpenAICompatibleProvider` a conversation on This iPhone uses:
/// its text arrives, its prompt progress is read, it finishes, and its
/// usage carries the context gglib loaded the model with, which raises the
/// ring. The fixture, not this test, says what gglib sent: the expectations
/// are read out of it on their own, so a recording made again is held to
/// the same reading.
final class PhoneStreamContractTests: XCTestCase {
    private let host = "phone-stream.test"

    /// What the fixture says, read without the provider: each content
    /// delta joined, the finish reason, and the usage frame's counts.
    private struct Recorded {
        var text = ""
        var finish: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var contextSize: Int?
    }

    private func recorded(_ bytes: Data) throws -> Recorded {
        var said = Recorded()
        for line in String(decoding: bytes, as: UTF8.self).split(separator: "\n") where line.hasPrefix("data: {") {
            let frame = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.dropFirst("data: ".count).utf8)) as? [String: Any])
            if let choice = (frame["choices"] as? [[String: Any]])?.first {
                said.text += (choice["delta"] as? [String: Any])?["content"] as? String ?? ""
                said.finish = choice["finish_reason"] as? String ?? said.finish
            }
            if let usage = frame["usage"] as? [String: Any] {
                said.promptTokens = usage["prompt_tokens"] as? Int
                said.completionTokens = usage["completion_tokens"] as? Int
                said.contextSize = usage["context_size"] as? Int
            }
        }
        return said
    }

    func testAReplyFromGglibsEngineOnThisIPhoneFinishesAndRaisesTheRing() async throws {
        let fixture = try Fixtures.data("phone-stream.sse")
        let expected = try recorded(fixture)
        let size = try XCTUnwrap(expected.contextSize, "the recording carries no context_size")
        XCTAssertGreaterThan(size, 0)
        XCTAssertFalse(expected.text.isEmpty, "the recording carries no text")

        let pieces = stride(from: 0, to: fixture.count, by: 97).map { fixture[$0..<min($0 + 97, fixture.count)] }
        StubURLProtocol.register(
            host: host, path: "/v1/chat/completions",
            .init(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: pieces))
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "http://\(host)/v1")!, apiKey: "engine-key", session: StubURLProtocol.makeSession(),
            log: NoopLogSink())
        let request = ChatRequest(
            model: "tinygemma3-Q8_0", messages: [Message(role: .user, content: "Say hello.", createdAt: .distantPast)],
            maxTokens: 16, returnProgress: true)
        var events: [ChatEvent] = []
        for await event in provider.stream(request) { events.append(event) }

        let text = events.compactMap { if case .delta(let text) = $0 { text } else { nil } }.joined()
        XCTAssertEqual(text, expected.text)
        XCTAssertTrue(
            events.contains { if case .progress = $0 { true } else { false } }, "the prompt's progress was not read")
        guard case .finished(let reason, let usage)? = events.last else {
            return XCTFail("the reply did not finish: \(String(describing: events.last))")
        }
        XCTAssertEqual(events.filter { if case .finished = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(reason, expected.finish)
        XCTAssertEqual(usage?.contextSize, size)
        let reading = try XCTUnwrap(ContextReading(usage, reason: reason, model: request.model), "no ring")
        XCTAssertEqual(reading.size, size)
        XCTAssertEqual(reading.used, (expected.promptTokens ?? 0) + (expected.completionTokens ?? 0))
        XCTAssertEqual(reading.cutOff, expected.finish == "length")
        let sent = try XCTUnwrap(StubURLProtocol.requests(host: host).first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer engine-key")
    }
}
