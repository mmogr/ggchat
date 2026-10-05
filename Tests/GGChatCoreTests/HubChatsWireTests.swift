import XCTest

@testable import GGChatCore

/// Replays the chat bodies gglib records (`contracts/chats/recorded.json`
/// there, copied here byte for byte as `gglib-chats-recorded.json` from the
/// gglib pull request #1278, the one that adds the Thinking choice)
/// against the Swift hub chat types, its `turn`, `image_turn` and
/// `thinking_turn` against the bodies this build sends to carry a chat on,
/// and its `upload` against how an image sent to the hub is named.
///
/// The opened chat remembers its thinking switched off, and ends with a turn
/// sent from a device whose reply did not finish: its finished reply's row
/// carries the counts, the context's size and why the call ended, and the
/// unfinished one only gglib's mark.
final class HubChatsWireTests: XCTestCase {
    private struct Recorded: Decodable {
        let list: HubChatList
        let open: HubChatOpen
        let turn: HubTurn
        let upload: ImageRef
        let imageTurn: HubTurn
        let thinkingTurn: HubTurn

        enum CodingKeys: String, CodingKey {
            case list, open, turn, upload
            case imageTurn = "image_turn"
            case thinkingTurn = "thinking_turn"
        }
    }

    private static let imageID = "8d5c68b0badbe2691f67bbaa4a8bfba6ff015a4c0e31860ceb388de709e6a84c"

    /// One recorded body as the hub sends it, as an object.
    private func recordedObject(_ key: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-chats-recorded.json"))
        return try XCTUnwrap((object as? [String: Any])?[key] as? [String: Any])
    }

    private func recorded() throws -> Recorded {
        try JSONDecoder().decode(Recorded.self, from: try Fixtures.data("gglib-chats-recorded.json"))
    }

    func testTheListReadsEveryChatNewestFirst() throws {
        let want = HubChatList(chats: [
            HubChatSummary(
                id: 12, title: "Why the build broke", modelID: 3, model: "qwen3-8b", updatedAt: "2026-09-30 09:14:21",
                liveRun: "chat-5b1e"),
            HubChatSummary(id: 9, title: "New Chat", updatedAt: "2026-09-29 18:02:41"),
        ])
        XCTAssertEqual(try recorded().list, want)
    }

    func testAnOpenedChatReadsItsConversationAndRows() throws {
        let open = try recorded().open
        XCTAssertEqual(
            open.conversation,
            HubConversation(
                id: 12, title: "Why the build broke", modelID: 3, systemPrompt: "You are a helpful assistant.",
                settings: HubChatSettings(thinking: .off), createdAt: "2026-09-30 09:12:30",
                updatedAt: "2026-09-30 09:14:21"))
        let fromDevice = HubMessageMetadata(device: "phone-7c2e")
        XCTAssertEqual(
            open.messages,
            [
                HubMessage(
                    id: 40, conversationID: 12, role: "user", content: "Why did the build break?",
                    createdAt: "2026-09-30 09:12:31", metadata: fromDevice,
                    images: [ImageRef(id: Self.imageID, mime: "image/png", width: 1280, height: 720)]),
                HubMessage(
                    id: 41, conversationID: 12, role: "assistant", content: "A dependency moved.",
                    createdAt: "2026-09-30 09:13:07", metadata: Self.finished),
                HubMessage(
                    id: 42, conversationID: 12, role: "user", content: "And how do I fix it?",
                    createdAt: "2026-09-30 09:14:02", metadata: fromDevice),
                HubMessage(
                    id: 43, conversationID: 12, role: "assistant", content: "Pin the",
                    createdAt: "2026-09-30 09:14:21", metadata: HubMessageMetadata(incomplete: true)),
            ])
    }

    /// What the recorded chat's finished reply carries beside it.
    private static let finished = HubMessageMetadata(
        device: "phone-7c2e", modelName: "qwen3-8b", promptTokens: 812, completionTokens: 96, contextSize: 8_192,
        finishReason: "stop")

    /// A reply's row says what its last model call counted, how large the
    /// context was, what was trimmed and why the call ended, in camel case,
    /// and carries gglib's mark on a reply that did not finish. Each is nil
    /// when the hub did not save it, and one that does not read costs only
    /// itself: the row keeps who made it and its other counts.
    func testARowsMetadataReadsItsCountsSizeAndTrim() throws {
        let rows = try recorded().open.messages
        XCTAssertEqual(rows[1].metadata, Self.finished)
        XCTAssertEqual(rows[0].metadata, HubMessageMetadata(device: "phone-7c2e"))
        XCTAssertNil(rows[0].metadata?.incomplete)
        XCTAssertNil(rows[0].metadata?.contextSize)
        XCTAssertEqual(rows[3].metadata, HubMessageMetadata(incomplete: true))

        func metadata(_ json: String) throws -> HubMessageMetadata {
            try JSONDecoder().decode(HubMessageMetadata.self, from: Data(json.utf8))
        }
        XCTAssertEqual(
            try metadata(#"{"device":"phone-7c2e","incomplete":true,"modelName":"qwen3-8b"}"#),
            HubMessageMetadata(device: "phone-7c2e", modelName: "qwen3-8b", incomplete: true))
        XCTAssertEqual(try metadata(#"{"incomplete":false}"#).incomplete, false)
        // The row gglib records for a reply that trimmed (`contracts/runs/turn_made.json`).
        XCTAssertEqual(
            try metadata(
                #"{"cachedTokens":2100,"completionTokens":496,"contextSize":8192,"device":"phone-7c2e","#
                    + #""finishReason":"stop","modelName":"Qwen3.8-27B","modelQuantization":"Q8_0","#
                    + #""promptTokens":3180,"trimmedMessages":3,"turnDurationMs":41000,"writingDurationMs":38200}"#),
            HubMessageMetadata(
                device: "phone-7c2e", modelName: "Qwen3.8-27B", promptTokens: 3_180, completionTokens: 496,
                contextSize: 8_192, trimmedMessages: 3, finishReason: "stop"))
        XCTAssertEqual(try metadata(#"{"promptTokens":9,"completionTokens":0}"#).completionTokens, 0)
        let odd = try metadata(
            #"{"device":"phone-7c2e","modelName":"m","promptTokens":812,"completionTokens":"96","#
                + #""contextSize":8192.5,"trimmedMessages":null,"finishReason":7,"incomplete":"yes"}"#)
        XCTAssertEqual(odd, HubMessageMetadata(device: "phone-7c2e", modelName: "m", promptTokens: 812))
        // Snake case is the stream's spelling, not a row's.
        XCTAssertEqual(try metadata(#"{"prompt_tokens":9,"context_size":8192}"#), HubMessageMetadata())
    }

    /// The turn reads as recorded, and is sent as exactly the recorded body:
    /// the hub refuses a turn with any key but these two.
    func testATurnIsTheRecordedBodyWithOnlyItsTwoKeys() throws {
        let turn = HubTurn(conversationID: 12, content: "And how do I fix it?")
        XCTAssertEqual(try recorded().turn, turn)
        let sent = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(turn)) as? [String: Any]
        let want = try recordedObject("turn")
        XCTAssertEqual(sent?.keys.sorted(), ["content", "conversation_id"])
        XCTAssertEqual(sent.map { $0 as NSDictionary }, want as NSDictionary)
    }

    /// A turn that changes the Thinking choice reads as recorded and is sent
    /// as exactly the recorded body: the two keys and the word. Turning it
    /// back on says `default`, and a turn that says nothing has no such key.
    func testATurnThatChangesThinkingIsTheRecordedBody() throws {
        let turn = HubTurn(conversationID: 12, content: "Answer in one line.", thinking: .off)
        XCTAssertEqual(try recorded().thinkingTurn, turn)
        func sent(_ turn: HubTurn) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(turn)) as? [String: Any])
        }
        XCTAssertEqual(try sent(turn).keys.sorted(), ["content", "conversation_id", "thinking"])
        XCTAssertEqual(try sent(turn) as NSDictionary, try recordedObject("thinking_turn") as NSDictionary)
        let back = HubTurn(conversationID: 12, content: "Answer in one line.", thinking: .default)
        XCTAssertEqual(try sent(back)["thinking"] as? String, "default")
        XCTAssertNotEqual(turn, back)
        let withImage = HubTurn(conversationID: 12, content: "", images: [Self.imageID], thinking: .off)
        XCTAssertEqual(try sent(withImage).keys.sorted(), ["content", "conversation_id", "images", "thinking"])
        XCTAssertNil(try recorded().turn.thinking)
        XCTAssertNil(try recorded().imageTurn.thinking)
        XCTAssertEqual(try JSONDecoder().decode(HubTurn.self, from: try JSONEncoder().encode(back)), back)
    }

    /// An opened chat says what the hub remembers of its Thinking choice,
    /// `off` or nothing, and the model its last run used. The settings' other
    /// keys are passed over, either of the two that does not read costs only
    /// itself, and settings that are not an object cost the chat its
    /// settings and not its rows.
    func testAnOpenedChatReadsTheThinkingItRemembersAndItsModel() throws {
        XCTAssertEqual(try recorded().open.conversation.settings, HubChatSettings(thinking: .off))
        func open(_ settings: String?) throws -> HubChatOpen {
            let key = settings.map { #""settings": \#($0), "# } ?? ""
            let json =
                #"{"conversation": {"id": 1, "title": "t", \#(key)"created_at": "a", "updated_at": "b"}, "#
                + #""messages": [{"id": 2, "conversation_id": 1, "role": "user", "content": "q", "created_at": "c"}]}"#
            return try JSONDecoder().decode(HubChatOpen.self, from: Data(json.utf8))
        }
        let cases: [(String?, HubChatSettings?)] = [
            (nil, nil), ("null", nil), ("3", nil), (#""off""#, nil), ("[]", nil),
            ("{}", HubChatSettings()),
            (#"{"max_iterations": 8}"#, HubChatSettings()),
            (
                #"{"model_name": "Qwen3.8-27B", "temperature": 0.7, "thinking": "off", "tools": ["a"]}"#,
                HubChatSettings(thinking: .off, modelName: "Qwen3.8-27B")
            ),
            (#"{"thinking": "default"}"#, HubChatSettings(thinking: .default)),
            (#"{"thinking": "loud", "model_name": "m"}"#, HubChatSettings(modelName: "m")),
            (#"{"thinking": "off", "model_name": 7}"#, HubChatSettings(thinking: .off)),
            (#"{"thinking": 0, "model_name": null}"#, HubChatSettings()),
            (#"{"reasoning_budget_tokens": 0, "modelName": "m"}"#, HubChatSettings()),
        ]
        for (settings, want) in cases {
            let chat = try open(settings)
            XCTAssertEqual(chat.conversation.settings, want, settings ?? "no settings")
            XCTAssertEqual(chat.messages.map(\.content), ["q"], settings ?? "no settings")
        }
    }

    /// A turn with images reads as recorded and is sent as exactly the
    /// recorded body: its text, then the ids of its images in order.
    func testATurnWithImagesIsTheRecordedBodyWithItsImageIDs() throws {
        let turn = HubTurn(conversationID: 12, content: "What does this error mean?", images: [Self.imageID])
        XCTAssertEqual(try recorded().imageTurn, turn)
        let sent = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(turn)) as? [String: Any]
        XCTAssertEqual(sent?.keys.sorted(), ["content", "conversation_id", "images"])
        XCTAssertEqual(sent.map { $0 as NSDictionary }, try recordedObject("image_turn") as NSDictionary)
        let alone = HubTurn(conversationID: 12, content: "", images: [Self.imageID, "ab"])
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(alone)) as? [String: Any]
        XCTAssertEqual(object?["content"] as? String, "")
        XCTAssertEqual(object?["images"] as? [String], [Self.imageID, "ab"])
    }

    /// The hub's answer to an upload names the image as a message's images
    /// do: its id, type and size. Its token estimate is passed over.
    func testAnUploadIsAnsweredWithTheImagesReference() throws {
        XCTAssertEqual(
            try recorded().upload, ImageRef(id: Self.imageID, mime: "image/png", width: 1280, height: 720))
        XCTAssertEqual(try recordedObject("upload")["image_tokens"] as? Int, 920)
    }

    /// gglib writes a conversation's model and prompt as `null` when it has
    /// none, and leaves a row's metadata out.
    func testNullAndMissingOptionalsDecodeAsNil() throws {
        let json = """
            {"conversation": {"id": 1, "title": "t", "model_id": null, "system_prompt": null,
                              "created_at": "a", "updated_at": "b"},
             "messages": [{"id": 2, "conversation_id": 1, "role": "tool", "content": "", "created_at": "c"}]}
            """
        let open = try JSONDecoder().decode(HubChatOpen.self, from: Data(json.utf8))
        XCTAssertEqual(open.conversation, HubConversation(id: 1, title: "t", createdAt: "a", updatedAt: "b"))
        XCTAssertEqual(open.messages, [HubMessage(id: 2, conversationID: 1, role: "tool", content: "", createdAt: "c")])
    }

    /// Metadata that is not an object, or whose device or model is not a
    /// string, costs its row the metadata and nothing else.
    func testMetadataThatCannotBeReadIsDroppedAndTheRowKept() throws {
        let json = """
            {"conversation": {"id": 1, "title": "t", "created_at": "a", "updated_at": "b"},
             "messages": [
               {"id": 2, "conversation_id": 1, "role": "user", "content": "q", "created_at": "c", "metadata": 3},
               {"id": 3, "conversation_id": 1, "role": "assistant", "content": "r", "created_at": "d",
                "metadata": {"device": 7}},
               {"id": 4, "conversation_id": 1, "role": "assistant", "content": "s", "created_at": "e",
                "metadata": {"modelName": ["m"], "device": "phone-7c2e"}}
             ]}
            """
        let open = try JSONDecoder().decode(HubChatOpen.self, from: Data(json.utf8))
        XCTAssertEqual(open.messages.map(\.content), ["q", "r", "s"])
        XCTAssertEqual(open.messages.map(\.metadata), [nil, nil, nil])
    }

    /// A key this build does not know, at any level, is passed over.
    func testUnknownKeysArePassedOver() throws {
        let json = """
            {"chats": [{"id": 5, "title": "t", "updated_at": "u", "pinned": true, "folder": {"name": "x"}}],
             "next": "cursor"}
            """
        let list = try JSONDecoder().decode(HubChatList.self, from: Data(json.utf8))
        XCTAssertEqual(list, HubChatList(chats: [HubChatSummary(id: 5, title: "t", updatedAt: "u")]))
    }

    /// A chat's time, as gglib's database writes it, reads as that moment in
    /// UTC, whatever zone this machine is in: here, ten hours east of it.
    func testAChatsTimeReadsAsUTC() throws {
        let text = try recorded().list.chats[0].updatedAt
        let machineZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Australia/Brisbane"))
        defer { NSTimeZone.default = machineZone }
        XCTAssertEqual(DateFormatter().timeZone.secondsFromGMT(), 10 * 3600, "a formatter would read UTC anyway")
        let date = try XCTUnwrap(HubChatSummary.date(fromUpdatedAt: text))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(
            parts, DateComponents(year: 2026, month: 9, day: 30, hour: 9, minute: 14, second: 21))
    }

    /// A time in any other shape, or not a time, reads as nothing.
    func testATimeInAnotherShapeReadsAsNothing() {
        for text in ["", "u", "2026-09-30", "2026-09-30T09:13:07Z", "2026-13-30 09:13:07", "30/09/2026 09:13:07"] {
            XCTAssertNil(HubChatSummary.date(fromUpdatedAt: text), text)
        }
    }
}
