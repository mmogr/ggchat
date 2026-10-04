import Foundation
import XCTest

@testable import GGChatCore

/// The images of the hub's chats against a fake hub: an upload is the
/// image's bytes and is answered with how the hub names it, a fetch answers
/// the bytes and keeps them nowhere, and each refusal means what it should.
final class HubImagesProviderTests: XCTestCase {
    private let image = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4])

    private func recorded(_ key: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-chats-recorded.json"))
        let part = try XCTUnwrap((object as? [String: Any])?[key])
        return String(decoding: try JSONSerialization.data(withJSONObject: part), as: UTF8.self)
    }

    private func refusal(_ code: String) -> String {
        #"{"error":{"message":"refused","type":"invalid_request_error","code":"\#(code)"}}"#
    }

    private func upload(at host: String) async -> Result<ImageRef, HubTurnFailure> {
        do throws(HubTurnFailure) {
            return .success(try await ChatsHub.provider(at: host).uploadImage(image, mime: "image/png"))
        } catch {
            return .failure(error)
        }
    }

    private func fetch(_ id: String, at host: String) async -> Result<Data, HubChatsFailure> {
        do throws(HubChatsFailure) {
            return .success(try await ChatsHub.provider(at: host).fetchImage(id: id))
        } catch {
            return .failure(error)
        }
    }

    /// An upload is a `POST` whose whole body is the image, with the key,
    /// and the hub's answer names it.
    func testAnImageIsUploadedAsItsBytesAndNamedAsTheHubAnswers() async throws {
        let host = "images-upload.test"
        ChatsHub.serve(.init(body: try recorded("upload")), at: "/v1/attachments", on: host)
        let named = try await upload(at: host).get()
        XCTAssertEqual(named.id, "8d5c68b0badbe2691f67bbaa4a8bfba6ff015a4c0e31860ceb388de709e6a84c")
        XCTAssertEqual([named.width, named.height], [1280, 720])
        let request = try XCTUnwrap(ChatsHub.requests(at: host).first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/v1/attachments")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.httpBody ?? request.bodyStreamData, image)
    }

    /// A gglib with no `attachments` route is one from before images; any
    /// other refusal carries its sentence, and no answer is a lost one.
    func testAnUploadToAGglibWithoutImagesTakesNoImagesAndTheRestAreRefusals() async throws {
        let older = "images-upload-older.test"
        ChatsHub.serve(.init(status: 404, body: "", type: "text/plain"), at: "/v1/attachments/x", on: older)
        let olderResult = await upload(at: older)
        XCTAssertEqual(olderResult, .failure(.takesNoImages))
        let large = "images-upload-large.test"
        ChatsHub.serve(.init(status: 413, body: refusal("image_too_large")), at: "/v1/attachments", on: large)
        let largeResult = await upload(at: large)
        XCTAssertEqual(
            largeResult, .failure(.refused(.server(status: 413, code: "image_too_large", message: "refused"))))
        guard case .failure(.lost(.transport)) = await upload(at: "images-upload-nobody.test") else {
            return XCTFail("no answer was not a lost upload")
        }
    }

    /// A fetch is a `GET` by id with the key, answered with the bytes as
    /// they were sent.
    func testAnImageIsFetchedAsItsBytes() async throws {
        let host = "images-fetch.test"
        ChatsHub.serve(.init(body: "", type: "image/png", bytes: image), at: "/v1/attachments/abc", on: host)
        let fetched = try await fetch("abc", at: host).get()
        XCTAssertEqual(fetched, image)
        let request = try XCTUnwrap(ChatsHub.requests(at: host).first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path(), "/v1/attachments/abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hub-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/png, image/jpeg")
    }

    /// An id the hub does not hold is not found, and a page that is not an
    /// image is a drop.
    func testAFetchTheHubCannotAnswerIsNotFoundOrADrop() async throws {
        let host = "images-fetch-refused.test"
        ChatsHub.serve(
            .init(status: 404, body: refusal("attachment_not_found")), at: "/v1/attachments/gone", on: host)
        ChatsHub.serve(.init(body: "<html>", type: "text/html"), at: "/v1/attachments/page", on: host)
        let gone = await fetch("gone", at: host)
        XCTAssertEqual(gone, .failure(.notFound))
        let page = await fetch("page", at: host)
        XCTAssertEqual(page, .failure(.dropped(.invalidResponse("the answer was not an image"))))
    }

    /// A Mac's image is held in memory only: the fetch asks for nothing
    /// cached, on a session with no cache, so an answer a cache would keep
    /// for an hour is not kept by the provider's own cache, which keeps the
    /// same answer to any other request.
    func testAFetchedImageIsNeverKeptInAURLCache() async throws {
        let host = "images-fetch-cache.test"
        let cache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 0)
        let cacheable = ChatsHub.Answer(body: "", type: "image/png", bytes: image, cacheable: true)
        ChatsHub.serve(cacheable, at: "/v1/attachments/abc", on: host)
        ChatsHub.serve(cacheable, at: "/v1/kept", on: host)
        let provider = ChatsHub.provider(at: host, cache: cache)

        let kept = provider.makeRequest(path: "kept", method: "GET", body: nil)
        _ = try await provider.perform(kept)
        try await waitForCache { cache.cachedResponse(for: kept) != nil }
        XCTAssertNotNil(cache.cachedResponse(for: kept), "this cache keeps nothing, so the test proves nothing")

        let fetched = try await provider.fetchImage(id: "abc")
        XCTAssertEqual(fetched, image)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(cache.cachedResponse(for: provider.imageRequest(id: "abc")), "the image was cached")
        XCTAssertEqual(provider.imageRequest(id: "abc").cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(provider.uncachedSession().configuration.urlCache)
    }

    private func waitForCache(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }
}
