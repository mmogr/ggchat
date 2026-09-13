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
            XCTAssertNotNil(
                ProviderError.server(status: 400, code: code.rawValue, message: "m").hint,
                "\(code.rawValue) draws no second line")
        }
        XCTAssertEqual(ProviderError.whereToLook(forCode: "something_new"), .unknown)
        XCTAssertEqual(ProviderError.whereToLook(forCode: nil), .unknown)
    }

    /// The side named is the side that *wrote* the refusal. modelpipe writes
    /// `bad_gateway` on the serving side, about a backend it reached and
    /// could not read, and can only write `incomplete_request` after the head
    /// has already gone upstream — which makes it "your upload stopped", not
    /// "your JSON is wrong". Both used to point at the other machine.
    /// gglib's `device_not_paired` is the same kind: it reads like this
    /// device's problem, and the serving machine's device gate writes it.
    func testTheSideNamedIsTheSideThatWroteTheRefusal() {
        let expectations: [(ProviderError.Code, WhereToLook)] = [
            (.badGateway, .servingSide),
            (.incompleteRequest, .connectingSide),
            (.invalidAPIKey, .servingSide),
            (.backendUnreachable, .servingSide),
            (.tunnelUnavailable, .connectingSide),
            (.badRequest, .request),
            (.deviceNotPaired, .servingSide),
        ]
        for (code, expected) in expectations {
            XCTAssertEqual(code.whereToLook, expected, code.rawValue)
        }
        // The string the gate puts on the wire, not only the case: a raw value
        // spelt wrong would pass every line above and reach nobody.
        XCTAssertEqual(ProviderError.whereToLook(forCode: "device_not_paired"), .servingSide)
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

    /// A key the serving machine no longer admits says so, instead of only
    /// naming that machine: the machine is doing its job, and what is wrong
    /// is this device's key. Every other code keeps its side's line.
    func testAKeyTheServingMachineNoLongerAdmitsSaysSo() {
        let refused = ProviderError.server(
            status: 401, code: "invalid_api_key", message: "invalid or missing bearer token")
        XCTAssertEqual(refused.whereToLook, .servingSide, "the side it names is unchanged")
        XCTAssertEqual(refused.hint, "The serving machine did not accept the key this app sent.")
        XCTAssertEqual(Failure(refused).hint, refused.hint, "a saved failure draws the same line")
        let wedged = ProviderError.server(status: 502, code: "bad_gateway", message: "bad gateway")
        XCTAssertEqual(wedged.hint, WhereToLook.servingSide.hint)
        XCTAssertNil(ProviderError.server(status: 418, code: "something_new", message: "?").hint)
        for code in ProviderError.Code.allCases where code != .invalidAPIKey {
            XCTAssertNil(code.hint, "\(code.rawValue) has a sentence of its own that no test reads")
        }
    }

    /// The side is saved with every failure, by its raw value, so the
    /// strings are part of what is on disk and do not move.
    func testWhereToLookRawValuesArePersistedAndDoNotMove() {
        XCTAssertEqual(
            [WhereToLook.servingSide, .connectingSide, .request, .waitAndRetry, .unknown].map(\.rawValue),
            ["servingSide", "connectingSide", "request", "waitAndRetry", "unknown"])
    }

    /// A failure saved by a later build, naming a side this one has never
    /// heard of, keeps its sentence and its code and reads the side as
    /// unknown, instead of losing the whole value over the line under it.
    func testAFailureSavedByALaterBuildKeepsItsSentence() throws {
        let saved = Data(#"{"message":"resting","code":"relay_resting","whereToLook":"relaySide"}"#.utf8)
        let failure = try JSONDecoder().decode(Failure.self, from: saved)
        XCTAssertEqual(failure, Failure(message: "resting", code: "relay_resting", whereToLook: .unknown))
        XCTAssertEqual(try JSONDecoder().decode(Failure.self, from: JSONEncoder().encode(failure)), failure)
    }

    /// A saved failure is drawn by this build's reading of its code, not by
    /// the side it was saved with, so a code filed under the wrong side once
    /// is filed right in old conversations too. A failure with no code keeps
    /// the side it was saved with.
    func testASavedFailureIsReadByTodaysMappingOfItsCode() {
        let filedWrong = Failure(message: "bad gateway", code: "bad_gateway", whereToLook: .connectingSide)
        XCTAssertEqual(filedWrong.hint, WhereToLook.servingSide.hint)
        let dropped = Failure(message: "gone", code: nil, whereToLook: .connectingSide)
        XCTAssertEqual(dropped.hint, WhereToLook.connectingSide.hint)
    }

    func testRedactionKeepsOnlySchemeHostPortPath() throws {
        let url = try XCTUnwrap(URL(string: "http://user:secret@example.test:8080/v1/models?key=abc#frag"))
        XCTAssertEqual(Redaction.describe(url), "http://example.test:8080/v1/models")
    }
}
