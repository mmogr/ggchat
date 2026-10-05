import XCTest

@testable import GGChatCore

/// Replays the worked examples of the context reading against
/// `ContextReading`. The file is gglib's, `contracts/context/readings.json`,
/// added by the gglib change that draws the same ring on its chat page (the
/// pull request stacked on #1273), and `gglib-context-readings.json` is a
/// copy of it, byte for byte. The file, not this build, says what is right:
/// a failure here is fixed in the code, or in the file on both sides at
/// once.
///
/// Each example's `given` is the counts as a chat stream's `usage` and an
/// agent run's `turn_usage` spell them, so it is read through both, and
/// through a saved row's metadata, which spells the same keys in camel case.
final class ContextContractTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let provider = OpenAICompatibleProvider(baseURL: URL(string: "http://contract.test/v1")!, apiKey: nil)

    private struct Expect: Decodable {
        let shown: Bool
        let used: Int?
        let percent: Int?
        let percentText: String?
        let severity: String?
        let spoken: String?
        let lines: [String]?

        enum CodingKeys: String, CodingKey {
            case shown, used, percent, severity, spoken, lines
            case percentText = "percent_text"
        }
    }

    /// The saved row's name for each key the contract gives a reply.
    private static let rowKeys = [
        "prompt_tokens": "promptTokens", "completion_tokens": "completionTokens", "context_size": "contextSize",
        "trimmed_messages": "trimmedMessages", "finish_reason": "finishReason", "incomplete": "incomplete",
    ]

    private func examples(_ key: String) throws -> [[String: Any]] {
        let file = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-context-readings.json"))
        return try XCTUnwrap((file as? [String: Any])?[key] as? [[String: Any]], "the file has no \(key)")
    }

    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// A reply as a saved row's metadata carries it. A key the contract adds
    /// that this replay does not know fails here, not silently.
    private func metadata(_ reply: [String: Any], _ name: String) throws -> HubMessageMetadata {
        var row: [String: Any] = [:]
        for (key, value) in reply {
            row[try XCTUnwrap(Self.rowKeys[key], "\(name): no row key for \(key)")] = value
        }
        return try JSONDecoder().decode(HubMessageMetadata.self, from: Data(try json(row).utf8))
    }

    /// The reading a chat run's reader makes of the example: the finish
    /// reason in one frame, then the counts inside `usage` in the next.
    private func fromAStream(_ given: [String: Any], _ name: String) throws -> ContextReading? {
        var usage = given
        let reason = usage.removeValue(forKey: "finish_reason") ?? NSNull()
        var reply = ReplyState()
        reply.yieldsUsage = true
        let finish = try json(["choices": [["delta": [String: Any](), "finish_reason": reason, "index": 0]]])
        guard case .yield(let before) = provider.read(SSEEvent(data: finish), into: &reply), before.isEmpty else {
            XCTFail("\(name): the finish frame was not read as one")
            return nil
        }
        let counts = try json(["choices": [Any](), "usage": usage])
        guard case .yield(let events) = provider.read(SSEEvent(data: counts), into: &reply),
            case .usage(let counted, let ended)? = events.first, events.count == 1
        else {
            XCTFail("\(name): the usage frame was not passed on")
            return nil
        }
        XCTAssertEqual(ended, given["finish_reason"] as? String, name)
        return ContextReading(counted, reason: ended)
    }

    /// The reading made of the example as an agent run's `turn_usage` event.
    private func fromATurn(_ given: [String: Any], _ name: String) throws -> ContextReading? {
        let event = given.merging(["type": "turn_usage", "duration_ms": 900]) { first, _ in first }
        let events = OpenAICompatibleProvider.agentEvents(SSEEvent(data: try json(event)))
        guard case .usage(let counted, let ended)? = events.first, events.count == 1 else {
            XCTFail("\(name): the turn's usage was not passed on")
            return nil
        }
        return ContextReading(counted, reason: ended)
    }

    /// Every worked reading, through each of the three ways one reaches this
    /// app: whether there is a ring at all, and then the count, the percent
    /// and its text, the severity, what VoiceOver says and the sheet's lines.
    func testEveryWorkedReadingIsDrawnAsTheContractSays() throws {
        let readings = try examples("readings")
        XCTAssertEqual(readings.count, 20, "the worked readings are not all here")
        var shown = 0
        for example in readings {
            let name = try XCTUnwrap(example["name"] as? String)
            let given = try XCTUnwrap(example["given"] as? [String: Any], name)
            let expect = try JSONDecoder().decode(
                Expect.self,
                from: try JSONSerialization.data(withJSONObject: try XCTUnwrap(example["expect"] as? [String: Any])))
            let carried = [
                "stream": try fromAStream(given, name), "turn": try fromATurn(given, name),
                "row": ContextReading(try metadata(given, name)),
            ]
            for (carrier, made) in carried {
                let what = "\(name), by \(carrier)"
                guard expect.shown else {
                    XCTAssertNil(made, what)
                    continue
                }
                let reading = try XCTUnwrap(made, what)
                XCTAssertEqual(reading.used, try XCTUnwrap(expect.used, what), what)
                XCTAssertEqual(reading.percent, try XCTUnwrap(expect.percent, what), what)
                XCTAssertEqual(reading.percentText(in: english), try XCTUnwrap(expect.percentText, what), what)
                XCTAssertEqual(reading.severity.rawValue, try XCTUnwrap(expect.severity, what), what)
                XCTAssertEqual(reading.spokenValue(in: english), try XCTUnwrap(expect.spoken, what), what)
                XCTAssertEqual(reading.lines(in: english), try XCTUnwrap(expect.lines, what), what)
            }
            if expect.shown { shown += 1 }
        }
        XCTAssertEqual(shown, 16, "not every example that draws a ring was read")
        XCTAssertEqual(readings.count - shown, 4, "not every example that draws none was read")
    }

    /// Every worked source: which of a chat's replies decides its reading,
    /// and that the rows read as that reply's own reading, or as none.
    func testEveryWorkedSourceNamesTheReplyThatDecides() throws {
        let sources = try examples("sources")
        XCTAssertEqual(sources.count, 9, "the worked sources are not all here")
        var decided = 0
        for example in sources {
            let name = try XCTUnwrap(example["name"] as? String)
            let replies = try XCTUnwrap(example["replies"] as? [[String: Any]], name).map { try metadata($0, name) }
            let want = try XCTUnwrap(example["decides"], "\(name): nothing says which reply decides")
            let decides = want as? Int
            XCTAssertTrue(decides != nil || want is NSNull, "\(name): decides is neither a place nor null")
            XCTAssertEqual(ContextReading.deciding(among: replies), decides, name)

            let rows = replies.enumerated().flatMap { index, reply in
                let id = Int64(index * 2)
                return [
                    HubMessage(id: id, conversationID: 1, role: "user", content: "q", createdAt: "t"),
                    HubMessage(
                        id: id + 1, conversationID: 1, role: "assistant", content: "a", createdAt: "t",
                        metadata: reply),
                ]
            }
            XCTAssertEqual(ContextReading.last(in: rows), decides.flatMap { ContextReading(replies[$0]) }, name)
            if decides != nil { decided += 1 }
        }
        XCTAssertEqual(decided, 7, "not every source with a reply that decides was read")
    }
}
