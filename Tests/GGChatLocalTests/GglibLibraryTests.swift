import GGChatCore
import GGLib
import XCTest

@testable import GGChatLocal

/// What `GglibLibrary` does around gglib's library, over a fake one: when it
/// opens it, that what it answers and what it throws are the app's own, and
/// that the reading each verdict is asked with reaches gglib as it was taken.
final class GglibLibraryTests: XCTestCase {
    private let reading = GGChatCore.DeviceReading(
        physicalBytes: 8 << 30, availableBytes: 6 << 30, isSimulator: false)

    /// An open that failed, a full disk say, is not kept: the next question
    /// opens again, and one that landed is kept for every question after.
    func testAFailedOpenIsNotKeptAndTheNextQuestionOpensAgain() async throws {
        let opener = Opener([.failure(.NoSpace), .success(FakeLibrary())])
        let library = GglibLibrary(open: { try opener.open() })

        do {
            _ = try await library.installed()
            XCTFail("an open that failed answered")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .noSpace)
        }
        let installed = try await library.installed()
        _ = try await library.search(query: "qwen", cursor: nil)

        XCTAssertEqual(installed, [])
        XCTAssertEqual(opener.opens, 2, "the library was opened again for a question, or not at all after a failure")
    }

    /// The scene pass pauses and resumes on every trip to the background, in
    /// every build. A library nothing has asked has no download to pause, so
    /// that opens nothing, and makes no folder; one that is open is told.
    func testPausingAndResumingOpenNothingButReachAnOpenLibrary() async throws {
        let fake = FakeLibrary()
        let opener = Opener([.success(fake)])
        let library = GglibLibrary(open: { try opener.open() })

        await library.pauseAll()
        await library.resumeAll()
        XCTAssertEqual(opener.opens, 0, "pausing opened the library")

        _ = try await library.installed()
        await library.pauseAll()
        await library.resumeAll()
        XCTAssertEqual(fake.said.pauses, 1)
        XCTAssertEqual(fake.said.resumes, 1)
    }

    /// Whatever gglib refuses, each call throws as the app says it: a
    /// repository that wants a token says so, rather than gglib's own debug
    /// rendering of the case.
    func testEveryQuestionThrowsGglibsRefusalAsTheAppSaysIt() async {
        let library = GglibLibrary(open: { FakeLibrary(failure: .AuthRequired) })
        let questions: [(String, @Sendable () async throws -> Void)] = [
            ("search", { _ = try await library.search(query: "gated", cursor: nil) }),
            ("quantizations", { [reading] in _ = try await library.quantizations(repo: "o/gated", reading: reading) }),
            ("installed", { _ = try await library.installed() }),
            ("remove", { try await library.remove(id: 1) }),
            ("download", { _ = try await library.download(repo: "o/gated", quantization: "Q4_K_M") }),
        ]
        for (name, question) in questions {
            do {
                try await question()
                XCTFail("\(name) answered")
            } catch {
                XCTAssertEqual(error as? OnDeviceError, .authRequired, name)
                XCTAssertTrue(error.localizedDescription.contains("needs a Hugging Face token"), name)
            }
        }
    }

    /// Answers come back as the app's own records, and the reading a verdict
    /// is asked with reaches gglib as the app took it.
    func testAnswersAreTheAppsOwnAndTheReadingReachesGglib() async throws {
        let why = GGLib.FitWhy(weightsBytes: 1, kvBytesPerToken: 2, budgetBytes: 3, trainedCtx: 4)
        let fake = FakeLibrary(
            suggestions: [
                GGLib.Suggestion(
                    repo: "o/r", quantization: "Q4_K_M", bytes: 1, verdict: .fits(ctx: 8_192), why: why,
                    rationale: "fits")
            ],
            page: GGLib.SearchPage(
                hits: [GGLib.SearchHit(repo: "o/r", likes: 1, downloads: 2, parametersB: nil, trainedCtx: 4)],
                nextCursor: nil),
            offers: [GGLib.QuantOffer(name: "Q4_K_M", totalBytes: 1, shardCount: 1, verdict: .tight(ctx: 4), why: why)])
        let library = GglibLibrary(open: { fake })

        let suggested = try await library.suggested(reading: reading)
        let page = try await library.search(query: "qwen", cursor: nil)
        let offers = try await library.quantizations(repo: "o/r", reading: reading)
        try await library.remove(id: 9)

        XCTAssertEqual(suggested.map(\.verdict), [.fits(ctx: 8_192)])
        XCTAssertEqual(page.hits.map(\.repo), ["o/r"])
        XCTAssertEqual(offers.map(\.verdict), [.tight(ctx: 4)])
        let asked = fake.said
        XCTAssertEqual(asked.readings, Array(repeating: GGLib.DeviceReading(reading), count: 2))
        XCTAssertEqual(asked.searches, ["qwen"])
        XCTAssertEqual(asked.removed, [9])
    }
}
