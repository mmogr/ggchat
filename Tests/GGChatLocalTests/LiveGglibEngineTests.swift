import Foundation
import GGChatCore
import XCTest

@testable import GGChatLocal

/// gglib's engine, really served on the Mac's slice, with tinygemma3 in its
/// library: `make test-live-engine`. Skipped unless `GGLIB_ENGINE_MODELS_DIR`
/// is set (`LiveEngineLibrary`), so never in CI.
final class LiveGglibEngineTests: XCTestCase {
    private var library: LiveEngineLibrary?

    override func tearDown() {
        library?.remove()
        super.tearDown()
    }

    /// Served, the engine lists its one model under the name it was added
    /// as; one reply streams through the ordinary provider and its usage
    /// carries the context; the status walks to ready with the model's id,
    /// the one the list gave, at that context; and the shutdown ends the
    /// watch on stopped.
    func testOneReplyStreamsFromGglibsEngineAndTheStatusWalksToReady() async throws {
        let live = try LiveEngineLibrary.make()
        library = live
        let session = try await live.engine.serve(reading: LiveEngineLibrary.reading)
        let status = session.status
        let following = Task {
            var said: [EngineStatus] = []
            for await step in status { said.append(step) }
            return said
        }
        let provider = OpenAICompatibleProvider(baseURL: session.baseURL, apiKey: session.apiKey)

        let listed = try await provider.models().map(\.id)
        XCTAssertEqual(listed, [live.name], "the proxy lists the model under another id")
        let model = try XCTUnwrap(listed.first)
        let request = ChatRequest(
            model: model, messages: [Message(role: .user, content: "Say hello.", createdAt: .distantPast)],
            maxTokens: 16, returnProgress: true)
        var reply = ""
        var events: [ChatEvent] = []
        for await event in provider.stream(request) {
            events.append(event)
            if case .delta(let text) = event { reply += text }
        }
        guard case .finished(let reason, let usage)? = events.last else {
            await session.shutdown()
            return XCTFail("the reply ended with \(String(describing: events.last))")
        }
        XCTAssertFalse(reply.isEmpty, "the reply carried no text")
        let reading = try XCTUnwrap(
            ContextReading(usage, reason: reason, model: model),
            "the usage raised no ring: \(String(describing: usage))")

        await session.shutdown()
        let said = await following.value
        XCTAssertEqual(said.first, .idle, "the stream did not start where a new engine stands")
        XCTAssertTrue(
            said.contains(.ready(model: model, nCtx: UInt64(reading.size))),
            "the status never said ready with \(model) at \(reading.size): \(said)")
        XCTAssertEqual(said.last, .stopped, "the shutdown did not end the watch on stopped")
        let after = session.status
        var afterSaid: [EngineStatus] = []
        for await step in after { afterSaid.append(step) }
        XCTAssertEqual(afterSaid, [.stopped], "a watch begun after the shutdown said \(afterSaid)")
    }
}
