import XCTest

@testable import GGChatCore

/// The context ring's reading: when there is one, how full it says the
/// context is, the sentences the sheet shows and what VoiceOver hears. The
/// arithmetic and the words are pinned against gglib's worked examples in
/// `ContextContractTests`; these name each rule on its own.
final class ContextReadingTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func reading(
        _ prompt: Int?, _ completion: Int?, of size: Int?, trimmed: Int? = nil, reason: String? = nil
    ) -> ContextReading? {
        ContextReading(
            promptTokens: prompt, completionTokens: completion, contextSize: size, trimmedMessages: trimmed,
            finishReason: reason)
    }

    /// No estimate, ever: a count gglib did not send is unknown, not zero,
    /// and a size of zero is no size. A count of zero is still a count. A
    /// number no context could hold is not a count, so nothing a server
    /// sends can overflow the arithmetic.
    func testAReadingNeedsBothCountsAndASize() throws {
        XCTAssertNil(reading(8_000, 200, of: nil))
        XCTAssertNil(reading(8_000, nil, of: 32_768))
        XCTAssertNil(reading(nil, 200, of: 32_768))
        XCTAssertNil(reading(8_000, 200, of: 0))
        XCTAssertNil(reading(8_000, 200, of: -1))
        XCTAssertNil(ContextReading(Usage(promptTokens: 8_000, completionTokens: 200), reason: "stop"))
        XCTAssertNil(ContextReading(nil, reason: "stop"))
        XCTAssertNil(ContextReading(HubMessageMetadata(promptTokens: 8_000, completionTokens: 200)))
        XCTAssertNil(ContextReading(nil as HubMessageMetadata?))

        XCTAssertEqual(try XCTUnwrap(reading(8_000, 0, of: 32_768)).used, 8_000)
        XCTAssertEqual(try XCTUnwrap(reading(0, 200, of: 32_768)).used, 200)

        let most = ContextReading.largestCount
        XCTAssertNil(reading(Int.max, Int.max, of: Int.max))
        XCTAssertNil(reading(most + 1, 0, of: 32_768))
        XCTAssertNil(reading(0, most + 1, of: 32_768))
        XCTAssertNil(reading(1, 1, of: most + 1))
        XCTAssertNil(reading(-1, 200, of: 32_768))
        XCTAssertNil(reading(8_000, -1, of: 32_768))
        let largest = try XCTUnwrap(reading(most, most, of: most))
        XCTAssertEqual(largest.used, 2 * most)
        XCTAssertEqual(largest.percent, 100)
        XCTAssertEqual(try XCTUnwrap(reading(most, 0, of: most)).percent, 100)
        XCTAssertEqual(try XCTUnwrap(reading(most / 2, 0, of: most)).percent, 50)
        // The largest is still itself once stored and read back.
        let stored = try JSONEncoder().encode(largest)
        XCTAssertEqual(try JSONDecoder().decode(ContextReading.self, from: stored), largest)
    }

    /// Used is the prompt and the completion of the one call. The percent is
    /// a whole number with a half rounded up, in whole-number division, and
    /// stops at a hundred while the counts stay true. The ring draws the
    /// share itself, the whole ring at most and a sliver at least.
    func testThePercentRoundsAHalfUpAndNeverPassesAHundred() throws {
        let quarter = try XCTUnwrap(reading(8_000, 200, of: 32_768))
        XCTAssertEqual(quarter.used, 8_200)
        XCTAssertEqual(quarter.size, 32_768)
        XCTAssertEqual(quarter.percent, 25)
        XCTAssertEqual(quarter.fraction, 8_200.0 / 32_768.0, accuracy: 1e-12)

        XCTAssertEqual(try XCTUnwrap(reading(137, 0, of: 200)).percent, 69, "68.5 rounds up")
        XCTAssertEqual(try XCTUnwrap(reading(130, 8, of: 200)).percent, 69)
        XCTAssertEqual(try XCTUnwrap(reading(130, 9, of: 200)).percent, 70, "69.5 rounds up")
        XCTAssertEqual(try XCTUnwrap(reading(1, 0, of: 200)).percent, 1, "0.5 rounds up")
        XCTAssertEqual(try XCTUnwrap(reading(1_988, 0, of: 2_000)).percent, 99, "99.4 rounds down")

        let past = try XCTUnwrap(reading(32_900, 100, of: 32_768))
        XCTAssertEqual(past.percent, 100)
        XCTAssertEqual(past.used, 33_000)
        XCTAssertEqual(past.fraction, 1)
        XCTAssertEqual(try XCTUnwrap(reading(32_000, 768, of: 32_768)).fraction, 1)

        let sliver = try XCTUnwrap(reading(100, 20, of: 131_072))
        XCTAssertEqual(sliver.percent, 0)
        XCTAssertEqual(sliver.fraction, ContextReading.leastDrawn)
        XCTAssertEqual(sliver.percentText(in: english), "<1%")
        XCTAssertEqual(quarter.percentText(in: english), "25%")
    }

    /// Plain under 70, a warning from 70 and danger from 90, each with a word
    /// to go with its colour.
    func testSeverityTurnsAtSeventyAndNinetyAndEachHasAWord() throws {
        let wanted: [(used: Int, severity: ContextReading.Severity)] = [
            (0, .normal), (69, .normal), (70, .warning), (89, .warning), (90, .danger), (100, .danger),
            (250, .danger),
        ]
        for want in wanted {
            let made = try XCTUnwrap(reading(want.used, 0, of: 100))
            XCTAssertEqual(made.percent, min(want.used, 100))
            XCTAssertEqual(made.severity, want.severity, "\(want.used) of 100")
        }
        XCTAssertNil(ContextReading.Severity.normal.word)
        XCTAssertEqual(ContextReading.Severity.warning.word, "filling up")
        XCTAssertEqual(ContextReading.Severity.danger.word, "almost full")
    }

    /// The colour is never alone: the figure stands beside the ring from 70
    /// percent and a mark sits in it from 90, and neither a percent sooner.
    func testTheFigureShowsFromSeventyAndTheMarkFromNinety() throws {
        for percent in [0, 69, 70, 89, 90, 100] {
            let made = try XCTUnwrap(reading(percent, 0, of: 100))
            XCTAssertEqual(made.percent, percent)
            XCTAssertEqual(made.showsFigure, percent >= 70, "the figure at \(percent) percent")
            XCTAssertEqual(made.showsMark, percent >= 90, "the mark at \(percent) percent")
        }
    }

    /// The sheet's sentences, in order: the counts, how full, what was
    /// trimmed (one message or several, and nothing for none) and a reply
    /// cut off, which only a finish reason of `length` is.
    func testTheSheetSaysTheCountsTheTrimAndACutOffReply() throws {
        let counts = "8,200 of 32,768 tokens (25%) after the last finished reply."
        XCTAssertEqual(try XCTUnwrap(reading(8_000, 200, of: 32_768, reason: "stop")).lines(in: english), [counts])
        XCTAssertEqual(
            try XCTUnwrap(reading(8_000, 200, of: 32_768, trimmed: 1)).lines(in: english),
            [counts, "1 earlier message was shortened or left out to fit."])
        XCTAssertEqual(
            try XCTUnwrap(reading(8_000, 200, of: 32_768, trimmed: 2)).lines(in: english),
            [counts, "2 earlier messages were shortened or left out to fit."])
        XCTAssertEqual(try XCTUnwrap(reading(8_000, 200, of: 32_768, trimmed: 0)).lines(in: english), [counts])
        XCTAssertEqual(try XCTUnwrap(reading(8_000, 200, of: 32_768, trimmed: -3)).lines(in: english), [counts])
        for reason in ["stop", "tool_calls", "Length", ""] {
            let ended = try XCTUnwrap(reading(8_000, 200, of: 32_768, reason: reason))
            XCTAssertFalse(ended.cutOff, reason)
            XCTAssertEqual(ended.lines(in: english), [counts], reason)
        }
        XCTAssertEqual(
            try XCTUnwrap(reading(8_000, 200, of: 32_768, reason: "length")).lines(in: english),
            [counts, "The last reply was cut off before it finished."])
        XCTAssertEqual(
            try XCTUnwrap(reading(32_000, 768, of: 32_768, trimmed: 1_200, reason: "length")).lines(in: english),
            [
                "32,768 of 32,768 tokens (100%) after the last finished reply.", "Context is almost full.",
                "1,200 earlier messages were shortened or left out to fit.",
                "The last reply was cut off before it finished.",
            ])
        XCTAssertEqual(
            try XCTUnwrap(reading(24_000, 400, of: 32_768)).lines(in: english),
            ["24,400 of 32,768 tokens (74%) after the last finished reply.", "Context is filling up."])
    }

    /// The numbers are in the locale's digits and grouping, in the sheet, on
    /// the ring and for VoiceOver; the words stay as they are.
    func testNumbersUseTheLocalesDigits() throws {
        let made = try XCTUnwrap(reading(24_000, 400, of: 32_768, trimmed: 12))
        let arabic = Locale(identifier: "ar_EG")
        XCTAssertEqual(
            made.lines(in: arabic),
            [
                "٢٤٬٤٠٠ of ٣٢٬٧٦٨ tokens (٧٤%) after the last finished reply.", "Context is filling up.",
                "١٢ earlier messages were shortened or left out to fit.",
            ])
        XCTAssertEqual(made.percentText(in: arabic), "٧٤%")
        XCTAssertEqual(made.spokenValue(in: arabic), "٧٤ percent of context used, filling up")
        XCTAssertEqual(
            made.lines(in: Locale(identifier: "de_DE")).first,
            "24.400 of 32.768 tokens (74%) after the last finished reply.")
        let sliver = try XCTUnwrap(reading(100, 20, of: 131_072, trimmed: 1))
        XCTAssertEqual(sliver.percentText(in: arabic), "<١%")
        XCTAssertEqual(sliver.spokenValue(in: arabic), "less than ١ percent of context used")
        XCTAssertEqual(sliver.lines(in: arabic).last, "١ earlier message was shortened or left out to fit.")
    }

    /// VoiceOver hears the figure at every level, and the word from 70.
    func testVoiceOverHearsThePercentAndTheSeverityWord() throws {
        let heard = try [(25, 0), (72, 0), (95, 0), (0, 1)].map { used, completion in
            try XCTUnwrap(reading(used, completion, of: used == 0 ? 1_000 : 100)).spokenValue(in: english)
        }
        XCTAssertEqual(
            heard,
            [
                "25 percent of context used", "72 percent of context used, filling up",
                "95 percent of context used, almost full", "less than 1 percent of context used",
            ])
    }

    /// A chat's reading is its newest reply's, whatever rows stand between,
    /// passing over a reply gglib marked incomplete that carries no counts.
    /// A newest reply with no size leaves no reading: an older reply's is
    /// never shown in its place. The recorded chat's rows read the same way:
    /// its last reply did not finish, so the one before it decides.
    func testTheNewestFinishedRowDecidesAChatsReading() throws {
        func row(_ id: Int64, _ role: String, _ metadata: HubMessageMetadata? = nil) -> HubMessage {
            HubMessage(id: id, conversationID: 1, role: role, content: "x", createdAt: "t", metadata: metadata)
        }
        let first = HubMessageMetadata(promptTokens: 8_000, completionTokens: 200, contextSize: 32_768)
        let second = HubMessageMetadata(
            promptTokens: 9_000, completionTokens: 300, contextSize: 32_768, trimmedMessages: 2,
            finishReason: "length")
        let stopped = HubMessageMetadata(device: "phone-7c2e", incomplete: true)
        let rows = [
            row(1, "system"), row(2, "user", HubMessageMetadata(device: "phone-7c2e")), row(3, "assistant", first),
            row(4, "user"), row(5, "assistant", second), row(6, "tool"), row(7, "user"),
        ]
        let newest = try XCTUnwrap(ContextReading.last(in: rows))
        XCTAssertEqual(newest, ContextReading(second))
        XCTAssertEqual(newest.used, 9_300)
        XCTAssertEqual(newest.trimmed, 2)
        XCTAssertTrue(newest.cutOff)
        XCTAssertNil(newest.model)
        XCTAssertEqual(ContextReading.last(in: rows + [row(8, "assistant", stopped)]), newest)

        let noSize = HubMessageMetadata(promptTokens: 9_500, completionTokens: 10)
        XCTAssertNil(ContextReading.last(in: rows + [row(8, "assistant", noSize)]), "an older reading was shown")
        XCTAssertNil(ContextReading.last(in: rows + [row(8, "assistant")]), "an older reading was shown")
        let counted = HubMessageMetadata(
            promptTokens: 9_500, completionTokens: 10, contextSize: 32_768, incomplete: true)
        XCTAssertEqual(ContextReading.last(in: rows + [row(8, "assistant", counted)])?.used, 9_510)
        XCTAssertNil(ContextReading.last(in: [row(1, "user", first), row(2, "tool", first)]), "not a reply's row")
        XCTAssertNil(ContextReading.last(in: []))

        struct Recorded: Decodable { let open: HubChatOpen }
        let recorded = try JSONDecoder().decode(Recorded.self, from: try Fixtures.data("gglib-chats-recorded.json"))
        XCTAssertEqual(recorded.open.messages.last?.metadata, HubMessageMetadata(incomplete: true))
        let saved = try XCTUnwrap(ContextReading.last(in: recorded.open.messages))
        XCTAssertEqual(saved.lines(in: english), ["908 of 8,192 tokens (11%) after the last finished reply."])
    }
}
