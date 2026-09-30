import XCTest

@testable import GGChatCore

/// Replays the chat bodies gglib records (`contracts/chats/recorded.json`
/// there, copied here as `gglib-chats-recorded.json` from gglib 8ca14391)
/// against the Swift hub chat types. The file's `turn` is for continuing a
/// chat, which this build does not do yet.
final class HubChatsWireTests: XCTestCase {
    private struct Recorded: Decodable {
        let list: HubChatList
        let open: HubChatOpen
    }

    private func recorded() throws -> Recorded {
        try JSONDecoder().decode(Recorded.self, from: try Fixtures.data("gglib-chats-recorded.json"))
    }

    func testTheListReadsEveryChatNewestFirst() throws {
        let want = HubChatList(chats: [
            HubChatSummary(
                id: 12, title: "Why the build broke", modelID: 3, model: "qwen3-8b", updatedAt: "2026-09-30 09:13:07",
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
                createdAt: "2026-09-30 09:12:30", updatedAt: "2026-09-30 09:13:07"))
        XCTAssertEqual(
            open.messages,
            [
                HubMessage(
                    id: 40, conversationID: 12, role: "user", content: "Why did the build break?",
                    createdAt: "2026-09-30 09:12:31", metadata: HubMessageMetadata(device: "phone-7c2e")),
                HubMessage(
                    id: 41, conversationID: 12, role: "assistant", content: "A dependency moved.",
                    createdAt: "2026-09-30 09:13:07",
                    metadata: HubMessageMetadata(device: "phone-7c2e", modelName: "qwen3-8b")),
            ])
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
}
