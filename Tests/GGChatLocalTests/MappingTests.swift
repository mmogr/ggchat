import GGChatCore
import GGLib
import XCTest

@testable import GGChatLocal

/// Each of gglib's library records and errors crosses into the app's own
/// type field for field and case for case, so nothing above GGChatLocal ever
/// reads one of gglib's as another.
final class MappingTests: XCTestCase {
    private let why = GGLib.FitWhy(
        weightsBytes: 1 << 30, kvBytesPerToken: 114_688, budgetBytes: 3 << 30, trainedCtx: 40_960)
    private let appsWhy = GGChatCore.FitWhy(
        weightsBytes: 1 << 30, kvBytesPerToken: 114_688, budgetBytes: 3 << 30, trainedCtx: 40_960)

    /// Every verdict, each input an unknown one can miss, and whether the
    /// head was cut off, which is all that tells "a download will say" from
    /// "nothing will".
    func testEachVerdictCrossesAsTheAppsOwn() {
        XCTAssertEqual(GGChatCore.FitVerdict(.fits(ctx: 16_384)), .fits(ctx: 16_384))
        XCTAssertEqual(GGChatCore.FitVerdict(.tight(ctx: 4_096)), .tight(ctx: 4_096))
        XCTAssertEqual(
            GGChatCore.FitVerdict(.tooBig(needBytes: 5 << 30, haveBytes: 3 << 30)),
            .tooBig(needBytes: 5 << 30, haveBytes: 3 << 30))
        let missing: [(GGLib.MissingInput, GGChatCore.MissingInput)] = [
            (.trainedContext, .trainedContext), (.kvShape, .kvShape), (.weights, .weights), (.budget, .budget),
        ]
        for (theirs, ours) in missing {
            for cutOff in [true, false] {
                XCTAssertEqual(
                    GGChatCore.FitVerdict(.unknown(missing: theirs, cutOff: cutOff)),
                    .unknown(missing: ours, cutOff: cutOff), "\(theirs), cut off \(cutOff)")
            }
        }
    }

    /// A figure gglib did not have stays absent, never zero.
    func testTheWhyCrossesFigureForFigureAndKeepsWhatIsUnknown() {
        XCTAssertEqual(GGChatCore.FitWhy(why), appsWhy)
        let partly = GGLib.FitWhy(weightsBytes: 7, kvBytesPerToken: nil, budgetBytes: nil, trainedCtx: 9)
        XCTAssertEqual(
            GGChatCore.FitWhy(partly),
            GGChatCore.FitWhy(weightsBytes: 7, kvBytesPerToken: nil, budgetBytes: nil, trainedCtx: 9))
    }

    func testEachBrowsedRecordCrossesFieldForField() {
        XCTAssertEqual(
            GGChatCore.Suggestion(
                GGLib.Suggestion(
                    repo: "o/r", quantization: "Q4_K_M", bytes: 3, verdict: .fits(ctx: 8_192), why: why,
                    rationale: "small")),
            GGChatCore.Suggestion(
                repo: "o/r", quantization: "Q4_K_M", bytes: 3, verdict: .fits(ctx: 8_192), why: appsWhy,
                rationale: "small"))
        let hit = GGLib.SearchHit(repo: "o/r", likes: 1, downloads: 2, parametersB: 1.7, trainedCtx: nil)
        XCTAssertEqual(
            GGChatCore.SearchPage(GGLib.SearchPage(hits: [hit], nextCursor: "2")),
            GGChatCore.SearchPage(
                hits: [GGChatCore.SearchHit(repo: "o/r", likes: 1, downloads: 2, parametersB: 1.7, trainedCtx: nil)],
                nextCursor: "2"))
        XCTAssertEqual(
            GGChatCore.QuantOffer(
                GGLib.QuantOffer(name: "Q8_0", totalBytes: 5, shardCount: 2, verdict: .tight(ctx: 4_096), why: why)),
            GGChatCore.QuantOffer(name: "Q8_0", totalBytes: 5, shardCount: 2, verdict: .tight(ctx: 4_096), why: appsWhy)
        )
        XCTAssertEqual(
            GGChatCore.InstalledModel(
                GGLib.InstalledModel(
                    id: 4, name: "Test model", bytes: 6, trainedCtx: 40_960, capabilities: ["reasoning"],
                    verdict: .unknown(missing: .budget, cutOff: false))),
            GGChatCore.InstalledModel(
                id: 4, name: "Test model", bytes: 6, trainedCtx: 40_960, capabilities: ["reasoning"],
                verdict: .unknown(missing: .budget, cutOff: false)))
    }

    /// The reading is the one record that goes the other way.
    func testTheReadingCrossesToGglibAsTheAppTookIt() {
        let reading = GGChatCore.DeviceReading(physicalBytes: 8 << 30, availableBytes: 6 << 30, isSimulator: true)
        XCTAssertEqual(
            GGLib.DeviceReading(reading),
            GGLib.DeviceReading(physicalBytes: 8 << 30, availableBytes: 6 << 30, isSimulator: true))
    }

    func testEachDownloadStateCrossesWithItsBytes() {
        let states: [(GGLib.DownloadState, GGChatCore.DownloadState)] = [
            (.queued, .queued), (.running, .running), (.paused, .paused), (.verifying, .verifying), (.done, .done),
            (.failed(reason: "the Hub hung up"), .failed(reason: "the Hub hung up")),
        ]
        for (theirs, ours) in states {
            XCTAssertEqual(
                GGChatCore.DownloadProgress(
                    GGLib.DownloadProgress(id: "o/r:Q4_K_M", bytes: 40, total: nil, state: theirs)),
                GGChatCore.DownloadProgress(id: "o/r:Q4_K_M", bytes: 40, total: nil, state: ours))
        }
    }

    /// Each of gglib's errors is the app's own case, so it is said as the app
    /// says it: a repository that wants a token says so.
    func testEachGglibErrorIsTheAppsOwnCase() {
        let errors: [(GglibError, OnDeviceError)] = [
            (.AuthRequired, .authRequired), (.NotFound, .notFound), (.RateLimited, .rateLimited),
            (.NoSpace, .noSpace), (.Network(message: "offline"), .network(message: "offline")),
            (.DoesNotFit(need: 5, have: 3), .doesNotFit(need: 5, have: 3)),
            (.EngineUnavailable, .engineUnavailable), (.Internal(message: "broke"), .internal(message: "broke")),
        ]
        for (theirs, ours) in errors {
            XCTAssertEqual(OnDeviceError(theirs), ours)
            XCTAssertEqual(OnDeviceError(thrown: theirs), ours)
        }
        XCTAssertEqual(OnDeviceError(thrown: OnDeviceError.noSpace), .noSpace)
        XCTAssertTrue(OnDeviceError(GglibError.AuthRequired).localizedDescription.contains("token"))
    }

    /// Anything else thrown through a call, which only uniffi's machinery
    /// throws, is an internal failure in its own words, never dropped.
    func testAnErrorThatIsNotGglibsIsInternalInItsOwnWords() {
        struct Machinery: Error, CustomStringConvertible {
            var description: String { "a buffer could not be read" }
        }
        XCTAssertEqual(OnDeviceError(thrown: Machinery()), .internal(message: "a buffer could not be read"))
    }
}
