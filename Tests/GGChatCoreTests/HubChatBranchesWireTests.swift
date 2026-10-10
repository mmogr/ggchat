import XCTest

@testable import GGChatCore

/// Replays the branching bodies gglib records (`contracts/chats/recorded.json`
/// there, copied here byte for byte as `gglib-chats-recorded.json` from gglib
/// pull request #1380) against the Swift hub types (ADR 0010): `branch_open`,
/// a branch made by an edit, read with its branch point; `change`, the edit
/// this build sends; `changed`, the Mac's answer; and `answer_turn`, the turn
/// that answers the branch's question.
final class HubChatBranchesWireTests: XCTestCase {
    /// One recorded body as the hub sends it, as an object.
    private func recordedObject(_ key: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-chats-recorded.json"))
        return try XCTUnwrap((object as? [String: Any])?[key] as? [String: Any])
    }

    private func recorded<T: Decodable>(_ key: String, as type: T.Type) throws -> T {
        let body = try JSONSerialization.data(withJSONObject: try recordedObject(key))
        return try JSONDecoder().decode(type, from: body)
    }

    private func sent(_ value: some Encodable) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(value)) as? NSDictionary)
    }

    /// The branch the edit made reads with its one branch point, at its
    /// question, the chat it was made from first, and says it ends in a
    /// question nothing answers.
    func testABranchOpensWithItsPointAndAnswerable() throws {
        let open = try recorded("branch_open", as: HubChatOpen.self)
        XCTAssertEqual(open.messages.map(\.id), [50, 51, 52])
        XCTAssertEqual(
            open.points,
            [
                BranchPoint(
                    messageID: 52, index: 1,
                    options: [
                        BranchOption(chatID: 12, messageID: 42, role: .user, preview: "And how do I fix it?"),
                        BranchOption(chatID: 13, messageID: 52, role: .user, preview: "And how do I pin it?"),
                    ])
            ])
        XCTAssertTrue(open.answerable)
        XCTAssertEqual(try sent(open)["points"] as? NSArray, try recordedObject("branch_open")["points"] as? NSArray)
    }

    /// A chat with no branches says neither, a list row says what it is a
    /// branch of, and points that cannot be read are dropped, the rows kept.
    func testAChatWithoutBranchesSaysNeither() throws {
        let open = try recorded("open", as: HubChatOpen.self)
        XCTAssertEqual(open.points, [])
        XCTAssertFalse(open.answerable)
        let encoded = try sent(open)
        XCTAssertNil(encoded["points"])
        XCTAssertNil(encoded["answerable"])
        let row = try JSONDecoder().decode(
            HubChatSummary.self, from: Data(#"{"id": 13, "title": "t", "updated_at": "u", "branch_of": 12}"#.utf8))
        XCTAssertEqual(row.branchOf, 12)
        let odd = try JSONDecoder().decode(
            HubChatOpen.self,
            from: Data(
                (#"{"conversation": {"id": 1, "title": "t", "created_at": "a", "updated_at": "b"}, "#
                    + #""messages": [{"id": 2, "conversation_id": 1, "role": "user", "content": "q", "#
                    + #""created_at": "c"}], "#
                    + #""points": [{"index": "first"}], "answerable": true}"#).utf8))
        XCTAssertEqual(odd.messages.map(\.content), ["q"], "a point that cannot be read cost the chat its rows")
        XCTAssertEqual(odd.points, [])
        XCTAssertTrue(odd.answerable)
    }

    /// The edit is sent as exactly the recorded body, its images only when
    /// it carries some; a regenerate and a branch name only the message.
    func testAChangeIsTheRecordedBody() throws {
        let edit = HubChatChange(.edit(messageID: 42, content: "And how do I pin it?", images: []))
        XCTAssertEqual(try sent(edit), try recordedObject("change") as NSDictionary)
        let withImage = HubChatChange(.edit(messageID: 42, content: "", images: ["ab"]))
        XCTAssertEqual(try sent(withImage)["images"] as? [String], ["ab"])
        XCTAssertEqual(
            try sent(HubChatChange(.regenerate(messageID: 43))), ["kind": "regenerate", "message_id": 43])
        XCTAssertEqual(try sent(HubChatChange(.branch(messageID: 41))), ["kind": "branch", "message_id": 41])
    }

    /// The Mac's answer names the branch, and that its question is to be
    /// answered by the recorded turn, which says `answer_saved` and no text.
    func testTheAnswerTurnIsTheRecordedBody() throws {
        XCTAssertEqual(
            try recorded("changed", as: HubChatChanged.self),
            HubChatChanged(conversationID: 13, forked: true, answer: true))
        let turn = HubTurn(conversationID: 13, content: "", answerSaved: true)
        XCTAssertEqual(try recorded("answer_turn", as: HubTurn.self), turn)
        XCTAssertEqual(try sent(turn), try recordedObject("answer_turn") as NSDictionary)
        XCTAssertNil(try sent(HubTurn(conversationID: 13, content: "q"))["answer_saved"])
    }

    /// A branch point names the row that starts its turn: a reply's first
    /// row, here one that only called a tool, so every row of a turn is
    /// keyed by it, and a system row by nothing.
    func testEachRowIsKeyedByTheRowThatStartsItsTurn() {
        func row(_ id: Int64, _ role: String) -> HubMessage {
            HubMessage(id: id, conversationID: 12, role: role, content: "", createdAt: "a")
        }
        let chat = HubChatOpen(
            conversation: HubConversation(id: 12, title: "t", createdAt: "a", updatedAt: "b"),
            messages: [row(39, "system"), row(40, "user"), row(41, "assistant"), row(42, "tool"), row(43, "assistant")])
        XCTAssertEqual(chat.turnStarts, [40: 40, 41: 41, 42: 41, 43: 41])
    }

    /// gglib refuses a change by its rules' codes, each with its status, and
    /// every one of them is a refusal that keeps its code: a row the chat no
    /// longer holds is a 404, and still not a chat that is gone.
    func testGglibsRefusalsOfAChangeKeepTheirCodes() async throws {
        let host = "chats-changes.test"
        let provider = ChatsHub.provider(at: host)
        for (status, code) in [
            (400, "not_a_reply"), (400, "unchanged"), (404, "message_not_found"), (409, "nothing_to_answer"),
        ] {
            let body = #"{"error":{"message":"no","type":"invalid_request_error","code":"\#(code)"}}"#
            ChatsHub.serve(.init(status: status, body: body), at: "/v1/chats/12/changes", on: host)
            do {
                _ = try await provider.changeChat(id: 12, change: HubChatChange(.regenerate(messageID: 41)))
                XCTFail("\(code) was taken for a change made")
            } catch {
                XCTAssertEqual(error, .refused(.server(status: status, code: code, message: "no")), code)
            }
        }
        let sent = try XCTUnwrap(ChatsHub.requests(at: host).last)
        XCTAssertEqual(sent.httpMethod, "POST")
    }
}
