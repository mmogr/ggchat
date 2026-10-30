import Foundation
import XCTest

@testable import GGChatCore
@testable import GGChatLocal

/// Records `Fixtures/phone-stream.sse`, which `PhoneStreamContractTests`
/// replays: the bytes gglib's proxy streams in front of its in-process
/// engine, on the Mac's slice, for the request ggchat sends, with the note
/// beside it of what made them. `make record-phone-stream` runs it; it
/// skips unless `GGCHAT_RECORD_PHONE_STREAM` is set, and needs what
/// `LiveEngineLibrary` needs.
final class PhoneStreamRecording: XCTestCase {
    private var library: LiveEngineLibrary?

    override func tearDown() {
        library?.remove()
        super.tearDown()
    }

    private static var fixtures: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures", directoryHint: .isDirectory)
    }

    func testRecordsThePhoneStream() async throws {
        guard ProcessInfo.processInfo.environment["GGCHAT_RECORD_PHONE_STREAM"] == "1" else {
            throw XCTSkip("GGCHAT_RECORD_PHONE_STREAM is not set; `make record-phone-stream` sets it")
        }
        let live = try LiveEngineLibrary.make()
        library = live
        let session = try await live.engine.serve(reading: LiveEngineLibrary.reading)
        let provider = OpenAICompatibleProvider(baseURL: session.baseURL, apiKey: session.apiKey)
        let chat = ChatRequest(
            model: live.name, messages: [Message(role: .user, content: "Say hello.", createdAt: .distantPast)],
            maxTokens: 16, returnProgress: true)
        let body = try JSONEncoder().encode(ChatCompletionRequest(chat))
        let request = provider.makeRequest(path: "chat/completions", method: "POST", body: body)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        await session.shutdown()
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let build = GGLibBuild.linked()
        let note = """
            phone-stream.sse is what gglib's proxy streamed in front of its in-process
            engine, recorded by `make record-phone-stream` (PhoneStreamRecording)
            through GglibEngine.serve() on the macOS slice, decoding on the CPU.
            gglib: \(build.gglibVersion)
            llama.cpp: \(build.llamaPin)
            uniffi: \(build.uniffiVersion)
            model: \(LiveEngineLibrary.modelFile), served as \(live.name)
            request: ggchat's own for a chat on This iPhone, "Say hello.",
            max_tokens 16, with return_progress and include_usage

            """
        try bytes.write(to: Self.fixtures.appending(path: "phone-stream.sse"))
        try Data(note.utf8).write(to: Self.fixtures.appending(path: "phone-stream.txt"))
    }
}
