import XCTest

@testable import GGChatCore

final class ErrorTests: XCTestCase {
    func testEveryDocumentedCodeNamesWhereToLook() {
        let expectations: [(String, WhereToLook)] = [
            ("invalid_api_key", .servingSide),
            ("backend_unreachable", .servingSide),
            ("tunnel_unavailable", .connectingSide),
            ("bad_gateway", .connectingSide),
            ("bad_request", .request),
            ("incomplete_request", .request),
            ("loop_detected", .request),
            ("stagnation_detected", .request),
            ("profile_not_found", .request),
            ("model_not_found", .request),
        ]
        for (code, expected) in expectations {
            XCTAssertEqual(ProviderError.whereToLook(forCode: code), expected, code)
        }
        XCTAssertEqual(ProviderError.whereToLook(forCode: "something_new"), .unknown)
        XCTAssertEqual(ProviderError.whereToLook(forCode: nil), .unknown)
    }

    func testServerMessageIsRenderedVerbatim() {
        let message = "Agentic loop detected: this conversation repeats the same tool-call batch."
        let error = ProviderError.server(status: 400, code: "loop_detected", message: message)
        XCTAssertEqual(error.errorDescription, message)
        XCTAssertEqual(error.whereToLook.hint, WhereToLook.request.hint)
    }

    func testServerErrorFromNonJSONBody() {
        let error = OpenAICompatibleProvider.serverError(status: 502, body: Data("<html>Bad Gateway</html>".utf8))
        XCTAssertEqual(error, .server(status: 502, code: nil, message: "<html>Bad Gateway</html>"))
        let empty = OpenAICompatibleProvider.serverError(status: 503, body: Data())
        XCTAssertEqual(empty, .server(status: 503, code: nil, message: "The server answered with HTTP 503."))
    }

    func testRedactionKeepsOnlySchemeHostPortPath() throws {
        let url = try XCTUnwrap(URL(string: "http://user:secret@example.test:8080/v1/models?key=abc#frag"))
        XCTAssertEqual(Redaction.describe(url), "http://example.test:8080/v1/models")
    }
}
