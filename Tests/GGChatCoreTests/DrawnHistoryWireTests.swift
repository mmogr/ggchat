import XCTest

@testable import GGChatCore

/// A reply's tool calls on the OpenAI wire: the request after a picture was
/// drawn says the call that made it and what the tool answered, to gglib
/// alone, so gglib can tell the model a picture was drawn (gglib's
/// `request_pipeline/drawn_note.rs`). The call and the answer are read from
/// the frames gglib recorded, `gglib-tool-progress.json`.
final class DrawnHistoryWireTests: XCTestCase {
    /// What the recorded frames say was called, and what it answered.
    static let call = ToolExchange(
        callID: "call_1", name: "builtin:generate_image",
        arguments: #"{"prompt":"a red fox in fresh snow, morning light"}"#)
    static let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
    private static let words = "I asked for a red fox in fresh snow."
    private static let picture = ImageRef(
        id: "8b6df8c11847ada8266bad5b8737f94c208c411a3ebe18e27aad31bfb7eb8767", mime: "image/png", width: 1024,
        height: 1024)

    /// The exchanges the recorded frames of a picture leave, as a reply
    /// being read gathers them.
    private func recorded() throws -> [ToolExchange] {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-tool-progress.json"))
        var exchanges: [ToolExchange] = []
        for frame in try XCTUnwrap(object as? [Any]) {
            let line = String(decoding: try JSONSerialization.data(withJSONObject: frame), as: UTF8.self)
            for event in OpenAICompatibleProvider.agentEvents(SSEEvent(data: line)) { exchanges.take(event) }
        }
        return exchanges
    }

    private func said(_ role: Role, _ text: String) -> Message {
        Message(role: role, content: text, createdAt: .distantPast)
    }

    /// The turn that drew: the question, and one reply holding the closing
    /// words, the picture and `exchanges`.
    private func drawn(_ exchanges: [ToolExchange], words: String = words) -> [Message] {
        var question = said(.user, "a fox in snow")
        question.draws = true
        var reply = said(.assistant, words)
        reply.images = [Self.picture]
        reply.exchanges = exchanges
        return [question, reply]
    }

    private func request(_ messages: [Message], replays: Bool = true) -> ChatRequest {
        ChatRequest(model: "m", messages: messages, replaysToolCalls: replays)
    }

    private func sortedJSON(_ request: ChatRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(ChatCompletionRequest(request)), as: UTF8.self)
    }

    /// The request's `messages`, as a server reads them.
    private func messages(_ request: ChatRequest) throws -> [[String: Any]] {
        let body = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(ChatCompletionRequest(request)))
        return try XCTUnwrap((body as? [String: Any])?["messages"] as? [[String: Any]])
    }

    private func roles(_ request: ChatRequest) throws -> [String] {
        try messages(request).compactMap { $0["role"] as? String }
    }

    /// gglib's rule for a history that holds a drawn picture, as
    /// `drawn_note.rs` writes it: an assistant message calls
    /// `builtin:generate_image`, and a later `tool` message with that
    /// call's id starts "Drew " and holds "the user can see ". An id's
    /// latest use is the one that counts.
    private func holdsADrawnPicture(_ messages: [[String: Any]]) -> Bool {
        var draws: [String: Bool] = [:]
        var drawn = false
        for message in messages {
            switch message["role"] as? String {
            case "assistant":
                for call in message["tool_calls"] as? [[String: Any]] ?? [] {
                    guard let id = call["id"] as? String else { continue }
                    draws[id] = (call["function"] as? [String: Any])?["name"] as? String == "builtin:generate_image"
                }
            case "tool":
                guard let id = message["tool_call_id"] as? String, draws[id] == true,
                    let text = message["content"] as? String
                else { continue }
                if text.hasPrefix("Drew "), text.contains("the user can see ") { drawn = true }
            default: break
            }
        }
        return drawn
    }

    /// The recorded frames of a picture leave one exchange: the call's id,
    /// the tool's name and the arguments the model wrote, as JSON text, and
    /// the tool's answer word for word, which it said worked.
    func testTheRecordedFramesOfAPictureLeaveItsCallAndItsAnswer() throws {
        var answered = Self.call
        answered.result = Self.drew
        answered.failed = false
        XCTAssertEqual(try recorded(), [answered])
    }

    /// The message after a picture: the question, the call, the tool's
    /// answer under the call's id, the reply's words, then the new message,
    /// in that order and in OpenAI's shape. The call has no `content` key,
    /// as gglib's own history has none, and no image is sent. It is the
    /// history gglib's rule reads as one that holds a drawn picture.
    func testTheMessageAfterAPictureCarriesTheCallItsAnswerThenTheWords() throws {
        let request = request(drawn(try recorded()) + [said(.user, "thanks")])
        XCTAssertEqual(
            try sortedJSON(request),
            #"{"messages":[{"content":"a fox in snow","role":"user"},"#
                + #"{"role":"assistant","tool_calls":[{"function":{"arguments":"#
                + #""{\"prompt\":\"a red fox in fresh snow, morning light\"}","name":"builtin:generate_image"},"#
                + #""id":"call_1","type":"function"}]},"#
                + #"{"content":"\#(Self.drew)","role":"tool","tool_call_id":"call_1"},"#
                + #"{"content":"\#(Self.words)","role":"assistant"},"#
                + #"{"content":"thanks","role":"user"}],"#
                + #""model":"m","stream":true,"stream_options":{"include_usage":true}}"#)
        XCTAssertTrue(holdsADrawnPicture(try messages(request)), "gglib would not read this as a drawn picture")
    }

    /// A server not known to be gglib is sent the reply's words alone, the
    /// bytes it was sent before a reply kept its calls; and a reply from
    /// before, which holds none, is sent to gglib as those same bytes.
    func testAnotherServerAndAReplyFromBeforeAreSentTheWordsAlone() throws {
        let kept = drawn(try recorded()) + [said(.user, "thanks")]
        let before = drawn([]) + [said(.user, "thanks")]
        let plain =
            #"{"messages":[{"content":"a fox in snow","role":"user"},"#
            + #"{"content":"\#(Self.words)","role":"assistant"},{"content":"thanks","role":"user"}],"#
            + #""model":"m","stream":true,"stream_options":{"include_usage":true}}"#
        XCTAssertEqual(try sortedJSON(request(kept, replays: false)), plain)
        XCTAssertEqual(try sortedJSON(request(before)), plain)
        XCTAssertFalse(holdsADrawnPicture(try messages(request(kept, replays: false))))
    }

    /// Two pictures are two calls, each answered under its own id, each
    /// ahead of its own reply's words, and so are two calls of one reply.
    func testTwoPicturesAreTwoCallsEachAnsweredUnderItsOwnID() throws {
        let first = try recorded()
        let second = [
            ToolExchange(
                callID: "call_2", name: Self.call.name, arguments: #"{"prompt":"a bluer fox"}"#, result: Self.drew)
        ]
        let history = drawn(first) + drawn(second, words: "A bluer one.") + [said(.user, "thanks")]
        let sent = try messages(request(history))
        XCTAssertEqual(
            sent.compactMap { $0["role"] as? String },
            ["user", "assistant", "tool", "assistant", "user", "assistant", "tool", "assistant", "user"])
        let called = sent.compactMap { ($0["tool_calls"] as? [[String: Any]])?.first }
        XCTAssertEqual(called.compactMap { $0["id"] as? String }, ["call_1", "call_2"])
        XCTAssertEqual(
            called.compactMap { ($0["function"] as? [String: Any])?["arguments"] as? String },
            [Self.call.arguments, #"{"prompt":"a bluer fox"}"#])
        XCTAssertEqual(sent.compactMap { $0["tool_call_id"] as? String }, ["call_1", "call_2"])
        XCTAssertEqual(
            sent.filter { $0["role"] as? String == "assistant" }.compactMap { $0["content"] as? String },
            [Self.words, "A bluer one."])

        // One reply that called twice: each call is followed by its own
        // answer, under its own id. Only a reply's calls are sent.
        var question = said(.user, "two foxes")
        question.exchanges = second
        var reply = said(.assistant, "Two foxes.")
        reply.exchanges = first + second
        let twice = try messages(request([question, reply]))
        XCTAssertEqual(
            twice.compactMap { $0["role"] as? String }, ["user", "assistant", "tool", "assistant", "tool", "assistant"])
        XCTAssertEqual(
            twice.compactMap { ($0["tool_calls"] as? [[String: Any]])?.first?["id"] as? String }, ["call_1", "call_2"])
        XCTAssertEqual(twice.compactMap { $0["tool_call_id"] as? String }, ["call_1", "call_2"])
    }

    /// A call nothing answered is left out, since a history may not hold
    /// one; a reply of a picture alone sends no empty words after its
    /// answer; and a draw that failed is sent with the tool's own error,
    /// which gglib's rule does not read as a picture.
    func testACallNothingAnsweredIsLeftOutAndAPictureAloneSendsNoEmptyWords() throws {
        XCTAssertEqual(try roles(request(drawn([Self.call]) + [said(.user, "thanks")])), ["user", "assistant", "user"])

        let alone = request(drawn(try recorded(), words: ""))
        XCTAssertEqual(try roles(alone), ["user", "assistant", "tool"])
        XCTAssertEqual(try roles(request(drawn([], words: ""))), ["user", "assistant"], "a reply from before changed")

        var failed = Self.call
        failed.result = "image_generation_failed: sd-server lost the render"
        let refused = request(drawn([failed], words: "The drawing tool failed.") + [said(.user, "why?")])
        XCTAssertEqual(try roles(refused), ["user", "assistant", "tool", "assistant", "user"])
        XCTAssertEqual(try messages(refused)[2]["content"] as? String, failed.result)
        XCTAssertFalse(holdsADrawnPicture(try messages(refused)))
    }

    /// A call's arguments are kept as JSON text whatever they came as, and
    /// a frame that names no call means no call. A call read a second time
    /// takes the place of the first, an answer goes on the call it names,
    /// and one for a call that is not held changes nothing.
    func testACallsArgumentsAreJSONTextAndAnAnswerGoesOnItsOwnCall() {
        func called(_ call: String) -> [ChatEvent] {
            OpenAICompatibleProvider.agentEvents(SSEEvent(data: #"{"type":"tool_call_start","tool_call":\#(call)}"#))
        }
        func exchange(_ arguments: String) -> [ChatEvent] {
            [.toolCalled(ToolExchange(callID: "c", name: "t", arguments: arguments))]
        }
        XCTAssertEqual(called(#"{"id":"c","name":"t","arguments":{"b":1,"a":"x/y"}}"#), exchange(#"{"a":"x/y","b":1}"#))
        XCTAssertEqual(called(#"{"id":"c","name":"t","arguments":"{\"a\":1}"}"#), exchange(#"{"a":1}"#))
        XCTAssertEqual(called(#"{"id":"c","name":"t"}"#), exchange("{}"))
        XCTAssertEqual(called(#"{"id":"c","name":"t","arguments":null}"#), exchange("{}"))
        XCTAssertEqual(called(#"{"name":"t","arguments":{}}"#), [])

        var held: [ToolExchange] = []
        held.take(.toolAnswered(callID: "c1", text: "too early"))
        XCTAssertEqual(held, [])
        held.take(.toolCalled(ToolExchange(callID: "c1", name: "one", arguments: "{}")))
        held.take(.toolCalled(ToolExchange(callID: "c2", name: "two", arguments: "{}")))
        held.take(.toolAnswered(callID: "c2", text: "second"))
        held.take(.delta("words"))
        XCTAssertEqual(held.map(\.result), [nil, "second"])
        held.take(.toolAnswered(callID: "c1", text: "first"))
        XCTAssertEqual(held.map(\.result), ["first", "second"])
        held.merge([ToolExchange(callID: "c1", name: "one", arguments: #"{"again":true}"#)])
        XCTAssertEqual(held.map(\.callID), ["c1", "c2"])
        XCTAssertEqual(held.map(\.arguments), [#"{"again":true}"#, "{}"])
    }

    /// A branch's copy of a reply keeps its calls, as it keeps its picture,
    /// and the rows the branching rules and the branch points read are the
    /// ones a reply with no calls gives.
    func testABranchKeepsAReplysCallsAndTheRowsAreUnchanged() throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let kept = Conversation(messages: drawn(try recorded()), createdAt: stamp, updatedAt: stamp)
        var before = kept
        before.messages[1].exchanges = []
        XCTAssertEqual(kept.branchRows, before.branchRows)
        XCTAssertEqual(kept.lineChat, before.lineChat)

        let branch = try kept.applying(.branch(messageID: kept.messages[1].id), busy: false, now: stamp).conversation
        XCTAssertEqual(branch.messages.map(\.exchanges), kept.messages.map(\.exchanges))
        XCTAssertEqual(branch.messages[1].images, [Self.picture])
        XCTAssertEqual(try roles(request(branch.messages + [said(.user, "thanks")])).count, 5)
    }
}
