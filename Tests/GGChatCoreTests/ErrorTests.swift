import XCTest

@testable import GGChatCore

final class ErrorTests: XCTestCase {
    /// The whole vocabulary, not a list maintained beside it. The list this
    /// replaces named ten codes while the switch handled eleven, so
    /// `invalid_request` was mapped and never checked, and the thirteen
    /// gglib codes nobody had mapped could not show up in it at all.
    /// Walking `allCases` means a code brings its own test with it, and the
    /// exhaustive switch behind `whereToLook` means it cannot be added
    /// without an answer.
    func testEveryDocumentedCodeNamesWhereToLook() {
        XCTAssertFalse(ProviderError.Code.allCases.isEmpty)
        for code in ProviderError.Code.allCases {
            XCTAssertNotEqual(
                ProviderError.whereToLook(forCode: code.rawValue), .unknown,
                "\(code.rawValue) is in the vocabulary and still says nothing")
            XCTAssertNotNil(code.whereToLook.hint, "\(code.rawValue) has no second line to show")
        }
        XCTAssertEqual(ProviderError.whereToLook(forCode: "something_new"), .unknown)
        XCTAssertEqual(ProviderError.whereToLook(forCode: nil), .unknown)
    }

    /// The side named is the side that *wrote* the refusal. modelpipe writes
    /// `bad_gateway` on the serving side, about a backend it reached and
    /// could not read, and can only write `incomplete_request` after the head
    /// has already gone upstream — which makes it "your upload stopped", not
    /// "your JSON is wrong". Both used to point at the other machine.
    func testTheSideNamedIsTheSideThatWroteTheRefusal() {
        let expectations: [(ProviderError.Code, WhereToLook)] = [
            (.badGateway, .servingSide),
            (.incompleteRequest, .connectingSide),
            (.invalidAPIKey, .servingSide),
            (.backendUnreachable, .servingSide),
            (.tunnelUnavailable, .connectingSide),
            (.badRequest, .request),
        ]
        for (code, expected) in expectations {
            XCTAssertEqual(code.whereToLook, expected, code.rawValue)
        }
    }

    /// A model still loading and a queue that never reached the request are
    /// not a machine to go and look at. Sending someone to inspect a machine
    /// that is doing its job is worse than saying nothing.
    func testAMachineThatIsMerelyBusySaysToWaitRatherThanNamingASide() {
        for code in [ProviderError.Code.modelLoading, .admissionTimeout, .upstreamTimeout] {
            XCTAssertEqual(code.whereToLook, .waitAndRetry, code.rawValue)
        }
        let loading = ProviderError.server(status: 503, code: "model_loading", message: "Model is loading, retry")
        XCTAssertEqual(loading.whereToLook, .waitAndRetry)
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
