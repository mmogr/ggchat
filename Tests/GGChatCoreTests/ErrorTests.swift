import XCTest

@testable import GGChatCore

#if canImport(CryptoKit)
    import CryptoKit
#endif

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

    /// The vocabulary is modelpipe's published list, `docs/error-codes-v0.json`
    /// at v0.6.0, vendored byte for byte, plus the codes only gglib writes. The
    /// two lists are a partition of the vocabulary's provenance, not of who
    /// can write a code in the wild: `invalid_pairing_code` is in modelpipe's
    /// list because its edge answers the pairing route from 0.6, and gglib
    /// has written the same code from its own route since v0.16.0. The list supplies
    /// the vocabulary and nothing else; which side to look at stays decided
    /// here, because `incomplete_request` is written by the serving side and
    /// still means "your upload stopped". The digest catches an edit by hand;
    /// a change upstream shows only when the copy is refreshed on purpose.
    func testThePublishedHalfOfTheVocabularyIsModelpipesOwnList() throws {
        let data = try Fixtures.data("modelpipe-error-codes-v0.json")
        #if canImport(CryptoKit)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(
                digest, "3bac9cebc2a933e2f663272e62d6d2cae296b7471358ca306405ebc1c993f5bc",
                "the vendored list differs from modelpipe v0.6.0's: refresh it from the tag, not by hand")
        #endif

        struct Published: Decodable {
            struct Entry: Decodable { let code: String }
            let codes: [Entry]
        }
        let publishedCodes = Set(try JSONDecoder().decode(Published.self, from: data).codes.map(\.code))

        let published: Set<ProviderError.Code> = [
            .invalidAPIKey, .badRequest, .badGateway, .backendUnreachable, .tunnelUnavailable,
            .incompleteRequest, .invalidPairingCode,
        ]
        let gglibOnly: Set<ProviderError.Code> = [
            .admissionTimeout, .contextLengthExceeded, .deviceNotPaired, .embeddingModelCannotChat,
            .hostNotAllowed, .internalError, .invalidRequest, .loopDetected, .mcpNotAllowedOverTunnel,
            .modelFileNotFound, .modelLoading, .modelNotFound, .notAnEmbeddingModel,
            .pinnedModelMismatch, .profileNotFound, .stagnationDetected, .upstreamError,
            .upstreamTimeout,
        ]
        XCTAssertEqual(
            Set(published.map(\.rawValue)), publishedCodes,
            "the published half here is not what modelpipe publishes")
        XCTAssertTrue(published.isDisjoint(with: gglibOnly), "a code is filed under both lists")
        XCTAssertEqual(
            published.union(gglibOnly), Set(ProviderError.Code.allCases),
            "a code in the vocabulary is filed under neither list")
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

    /// An error written into a stream keeps its code, so it names the same
    /// side a refusal with that code would, and its sentence is framed as a
    /// reply that stopped rather than shown as a bare socket message.
    func testAnErrorWrittenIntoAStreamKeepsItsCodeAndItsSentence() {
        let broke = ProviderError.stream(code: "upstream_error", message: "error decoding response body")
        XCTAssertEqual(broke.errorDescription, "The reply stopped: error decoding response body")
        XCTAssertEqual(broke.code, "upstream_error")
        XCTAssertEqual(broke.whereToLook, .servingSide)
        let waited = ProviderError.stream(code: "upstream_timeout", message: "upstream did not respond within 300s")
        XCTAssertEqual(waited.whereToLook, .waitAndRetry)
        XCTAssertEqual(waited.hint, WhereToLook.waitAndRetry.hint)
        XCTAssertEqual(ProviderError.stream(code: nil, message: "m").whereToLook, .unknown)
    }

    func testRedactionKeepsOnlySchemeHostPortPath() throws {
        let url = try XCTUnwrap(URL(string: "http://user:secret@example.test:8080/v1/models?key=abc#frag"))
        XCTAssertEqual(Redaction.describe(url), "http://example.test:8080/v1/models")
    }
}
