import Foundation
import XCTest

@testable import GGChatCore

/// The chats client against a fake hub: where it asks, with what key, and
/// what each refusal means.
final class HubChatsProviderTests: XCTestCase {
    private static let notNamed =
        #"{"error":{"message":"no","type":"invalid_request_error","code":"device_not_named"}}"#

    /// One recorded body, `list` or `open`, as the hub sends it.
    private func recorded(_ key: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-chats-recorded.json"))
        let part = try XCTUnwrap((object as? [String: Any])?[key])
        return String(decoding: try JSONSerialization.data(withJSONObject: part), as: UTF8.self)
    }

    private func failure<T>(_ body: () async throws(HubChatsFailure) -> T) async -> HubChatsFailure? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    func testTheListIsReadFromChatsWithTheKey() async throws {
        let host = "chats-list.test"
        ChatsHub.serve(.init(body: try recorded("list")), at: "/v1/chats", on: host)
        let list = try await ChatsHub.provider(at: host).listChats()
        XCTAssertEqual(list.chats.map(\.id), [12, 9])
        XCTAssertEqual(list.chats.first?.liveRun, "chat-5b1e")
        let request = try XCTUnwrap(ChatsHub.requests(at: host).first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path(), "/v1/chats")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        XCTAssertNil(request.httpBody)
    }

    func testAChatIsOpenedByItsIDWithTheKey() async throws {
        let host = "chats-open.test"
        ChatsHub.serve(.init(body: try recorded("open")), at: "/v1/chats/12", on: host)
        let open = try await ChatsHub.provider(at: host).openChat(id: 12)
        XCTAssertEqual(open.conversation.title, "Why the build broke")
        XCTAssertEqual(
            open.messages.map(\.content),
            ["Why did the build break?", "A dependency moved.", "And how do I fix it?", "Pin the"])
        let request = try XCTUnwrap(ChatsHub.requests(at: host).first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path(), "/v1/chats/12")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
    }

    /// A hub reached some way other than its tunnel from a paired device
    /// shares none of its chats, and says so with its own code.
    func testDeviceNotNamedIsAHubThatDoesNotShareItsChats() async throws {
        let host = "chats-not-named.test"
        let refusal = ChatsHub.Answer(status: 403, body: Self.notNamed)
        ChatsHub.serve(refusal, at: "/v1/chats", on: host)
        ChatsHub.serve(refusal, at: "/v1/chats/12", on: host)
        let provider = ChatsHub.provider(at: host)
        let listed = await failure { () async throws(HubChatsFailure) in try await provider.listChats() }
        XCTAssertEqual(listed, .notShared)
        let opened = await failure { () async throws(HubChatsFailure) in try await provider.openChat(id: 12) }
        XCTAssertEqual(opened, .notShared)
    }

    /// Only `device_not_named` is a hub that does not share: another 403 is
    /// the device gate's, and a refusal.
    func testAnother403IsARefusal() async throws {
        let host = "chats-forbidden.test"
        let body = #"{"error":{"message":"forgotten","type":"invalid_request_error","code":"device_forgotten"}}"#
        ChatsHub.serve(.init(status: 403, body: body), at: "/v1/chats", on: host)
        let provider = ChatsHub.provider(at: host)
        let listed = await failure { () async throws(HubChatsFailure) in try await provider.listChats() }
        XCTAssertEqual(
            listed, .refused(.server(status: 403, code: "device_forgotten", message: "forgotten")))
    }

    /// A chat the hub does not have, and a hub with no chats route at all.
    func testA404IsNotFound() async throws {
        let host = "chats-missing.test"
        let body = #"{"error":{"message":"not found","type":"invalid_request_error","code":"not_found"}}"#
        ChatsHub.serve(.init(status: 404, body: body), at: "/v1/chats/7", on: host)
        let provider = ChatsHub.provider(at: host)
        let opened = await failure { () async throws(HubChatsFailure) in try await provider.openChat(id: 7) }
        XCTAssertEqual(opened, .notFound)
        XCTAssertEqual(ChatsHub.requests(at: host).first?.url?.path(), "/v1/chats/7")
        let listed = await failure { () async throws(HubChatsFailure) in try await provider.listChats() }
        XCTAssertEqual(listed, .notFound, "an older gglib's bare 404")
    }

    /// A page in front of the hub, a 5xx, and no answer at all are drops:
    /// the hub may well answer later.
    func testAPageThatIsNotJSONA5xxAndNoAnswerAreDrops() async throws {
        let host = "chats-portal.test"
        ChatsHub.serve(.init(body: "<html>sign in</html>", type: "text/html"), at: "/v1/chats", on: host)
        let unavailable = #"{"error":{"message":"no chats","type":"service_unavailable","code":"chats_unavailable"}}"#
        ChatsHub.serve(.init(status: 503, body: unavailable), at: "/v1/chats/12", on: host)
        let provider = ChatsHub.provider(at: host)
        let portal = await failure { () async throws(HubChatsFailure) in try await provider.listChats() }
        XCTAssertEqual(portal, .dropped(.invalidResponse("the answer was not JSON")))
        let busy = await failure { () async throws(HubChatsFailure) in try await provider.openChat(id: 12) }
        XCTAssertEqual(busy, .dropped(.server(status: 503, code: "chats_unavailable", message: "no chats")))
        let away = ChatsHub.provider(at: "chats-nobody.test")
        let nobody = await failure { () async throws(HubChatsFailure) in try await away.listChats() }
        guard case .dropped(.transport?)? = nobody else { return XCTFail("no answer at all was not a drop") }
    }

    /// JSON that is not a chat list is the hub, or something like it, sending
    /// what this build cannot read, and asking again gets the same.
    func testJSONThatCannotBeReadIsARefusal() async throws {
        let host = "chats-odd.test"
        ChatsHub.serve(.init(body: #"{"chats": "none"}"#), at: "/v1/chats", on: host)
        let provider = ChatsHub.provider(at: host)
        let odd = await failure { () async throws(HubChatsFailure) in try await provider.listChats() }
        guard case .refused(.decoding)? = odd else { return XCTFail("a body that cannot be read was not a refusal") }
    }
}
