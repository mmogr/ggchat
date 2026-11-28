import Foundation
import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// Each tool a reply calls is a row while the reply is written, on both
/// doors, a reply kept here and a turn on one of the Mac's chats: it runs,
/// then is done with how long it took, in gglib's words, or failed, changed
/// in place by its call's id.
@MainActor
final class LiveRowsTests: XCTestCase {
    /// The recorded agent run's frames, each read as the decoder reads it,
    /// from the fixture the core tests read, beside this file's package.
    private static func recordedFrames() throws -> [[ChatEvent]] {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "GGChatCoreTests/Fixtures/gglib-agent-run-events.jsonl")
        return String(decoding: try Data(contentsOf: file), as: UTF8.self).split(separator: "\n")
            .map { OpenAICompatibleProvider.agentEvents(SSEEvent(data: String($0))) }
    }

    /// A row as one line to compare: its place, its text, its state and its
    /// detail.
    private static func shown(_ rows: [LiveRow]) -> [String] {
        rows.map { "\($0.id) \($0.text) | \($0.state) | \($0.detail ?? "-")" }
    }

    private static let read = "0 Read File: Cargo.lock | running | -"
    private static let readDone = "0 Read File: Cargo.lock | done | 3ms"
    private static let list = "1 List Dir | running | -"
    private static let plot = "2 Plot Chart: build times | running | -"
    private static let plotDone = "2 Plot Chart: build times | done | 40ms"
    private static let search = "3 Tavily Search: cargo lock v4 | running | -"
    private static let searchFailed = "3 Tavily Search: cargo lock v4 | failed | failed"

    /// What the reply shows after each of the recorded run's frames.
    private static let after: [[String]] = [
        [], [], [], [read], [readDone], [readDone], [readDone, list], [readDone, list, plot],
        [readDone, list, plotDone], [readDone, list, plotDone, search], [readDone, list, plotDone, searchFailed],
        [readDone, list, plotDone, searchFailed], [readDone, list, plotDone, searchFailed],
        [readDone, list, plotDone, searchFailed], [readDone, list, plotDone, searchFailed],
    ]

    /// Read frame by frame, as both doors apply a frame, each call's row
    /// comes in the order called and runs until its call ends; then it is
    /// done, with the duration gglib wrote, or failed. A call that ends
    /// while one before it still runs settles only its own row, and the
    /// call that never ended runs on. Every row keeps its place.
    func testEachCallIsARowThatRunsThenIsDoneOrFailedOnBothDoors() async throws {
        let (model, _) = try await AppModelRunTests.makeModel(behind: FakeRunHub(frames: []))
        let kept = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        let turn = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: nil)
        let frames = try Self.recordedFrames()
        XCTAssertEqual(frames.count, Self.after.count, "the recording changed")
        for (index, (frame, shown)) in zip(frames, Self.after).enumerated() {
            for event in frame {
                model.apply(event, to: kept)
                turn.apply(event)
            }
            XCTAssertEqual(Self.shown(kept.rows), shown, "a reply kept here, after frame \(index + 1)")
            XCTAssertEqual(Self.shown(turn.rows), shown, "a turn on the Mac's chat, after frame \(index + 1)")
        }
        XCTAssertEqual(kept.rows.map(\.callID), ["c1", "c2", "c3", "c4"])
        XCTAssertEqual(turn.rows.map(\.callID), ["c1", "c2", "c3", "c4"])
        XCTAssertEqual(
            kept.tools,
            ["Read File: Cargo.lock", "List Dir", "Plot Chart: build times", "Tavily Search: cargo lock v4"])
        XCTAssertEqual(kept.exchanges.map(\.callID), ["c1", "c2", "c3", "c4"], "the rows took the calls' place")
    }

    /// A call's end alone settles its row as done, with no time said, and
    /// an answer that does not say whether it failed is done too. A call
    /// whose start had no line of its own names no other call's row, not
    /// even one whose own call never came, so its end changes nothing, and
    /// nor does an end no row is waiting for. Both doors.
    func testARowIsSettledByItsOwnCallAndNoOther() async throws {
        let (model, _) = try await AppModelRunTests.makeModel(behind: FakeRunHub(frames: []))
        let kept = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        let turn = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: nil)
        func take(_ events: ChatEvent...) {
            for event in events {
                model.apply(event, to: kept)
                turn.apply(event)
            }
        }
        func shows(_ shown: [String], line: UInt = #line) {
            XCTAssertEqual(Self.shown(kept.rows), shown, "a reply kept here", line: line)
            XCTAssertEqual(Self.shown(turn.rows), shown, "a turn on the Mac's chat", line: line)
        }
        take(
            .tool("Read File: a"), .toolCalled(ToolExchange(callID: "a", name: "read", arguments: "{}")),
            .toolEnded("a"))
        shows(["0 Read File: a | done | -"])

        take(
            .tool("Search: b"), .delta("Looking. "),
            .toolCalled(ToolExchange(callID: "b", name: "unnamed", arguments: "{}")), .toolEnded("b"),
            .toolAnswered(callID: "b", text: "no", failed: true, duration: "9ms"),
            .toolAnswered(callID: "z", text: "no", failed: true))
        shows(["0 Read File: a | done | -", "1 Search: b | running | -"])
        XCTAssertEqual(kept.rows.map(\.callID), ["a", nil])
        XCTAssertEqual(turn.rows.map(\.callID), ["a", nil])

        take(.toolAnswered(callID: "a", text: "yes", failed: nil, duration: "2ms"))
        shows(["0 Read File: a | done | 2ms", "1 Search: b | running | -"])
    }

    /// A call the model is still writing is a running row that its call's
    /// own line takes the place of, keeping the row's place, and that call
    /// then settles that row.
    func testACallBeingWrittenBecomesItsCallsRowInPlace() {
        var rows = LiveRows()
        rows.take(.tool("Writing Generate Image\u{2026} 512 tokens", writing: true))
        XCTAssertEqual(Self.shown(rows.rows), ["0 Writing Generate Image\u{2026} 512 tokens | running | -"])
        rows.take(.tool("Generate Image: a fox"))
        rows.take(.toolCalled(ToolExchange(callID: "d", name: "draw", arguments: "{}")))
        rows.take(.toolEnded("d"))
        rows.take(.toolAnswered(callID: "d", text: "Drew 1 image", failed: false, duration: "76.0s"))
        XCTAssertEqual(Self.shown(rows.rows), ["0 Generate Image: a fox | done | 76.0s"])
    }

    /// Each state has its own mark, so none is told by colour alone, and a
    /// failed row says so after its text. VoiceOver hears the state in
    /// words, as gglib's window says it: "X done." and "X failed.", and how
    /// long a call that is done took.
    func testEachStateHasItsMarkAndItsWords() {
        let marks = [LiveRow.State.running, .done, .failed].map(LiveRowView.mark)
        XCTAssertEqual(marks, ["circle.dotted", "checkmark.circle", "exclamationmark.triangle.fill"])
        XCTAssertEqual(Set(marks).count, 3)

        var row = LiveRow(id: 0, kind: .tool, text: "Read File: Cargo.lock", state: .running)
        XCTAssertEqual(row.spoken, "Read File: Cargo.lock running.")
        XCTAssertNil(row.spokenTime)
        row.state = .done
        row.detail = "3ms"
        XCTAssertEqual(row.spoken, "Read File: Cargo.lock done.")
        XCTAssertEqual(row.spokenTime, "3ms")
        row.state = .failed
        row.detail = LiveRow.failedWord
        XCTAssertEqual(row.spoken, "Read File: Cargo.lock failed.")
        XCTAssertNil(row.spokenTime, "a failed row was heard twice as failed")
        XCTAssertEqual(LiveRow.failedWord, "failed")
        XCTAssertEqual(LiveRowView.identifier(for: .tool), "live-tool-row")
    }

    /// The rows found under a view, as the list that draws them holds them,
    /// or nil when there is none.
    private func list(in value: Any, depth: Int = 0) -> [LiveRow]? {
        if let found = value as? LiveRowsView { return found.rows }
        guard depth < 40 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = list(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    /// A Mac's reply draws its rows as the one list every reply draws, from
    /// the reply's rows and not their text, and that list draws a row for
    /// each, in order.
    func testAMacsReplyDrawsItsRowsAsTheOneList() {
        let reply = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: nil)
        reply.apply(.tool("Read File: Cargo.lock"))
        reply.apply(.toolCalled(ToolExchange(callID: "c1", name: "read", arguments: "{}")))
        reply.apply(.toolEnded("c1"))
        reply.apply(.toolAnswered(callID: "c1", text: "version = 3", failed: false, duration: "3ms"))
        reply.apply(.tool("List Dir"))
        XCTAssertEqual(list(in: HubLiveReplyRows(reply: reply, rows: .read([])).body), reply.rows)
        let drawn = Mirror(reflecting: LiveRowsView(rows: reply.rows).body).children.first { $0.label == "data" }
        XCTAssertEqual(drawn?.value as? [LiveRow], reply.rows)
    }

    /// A reply kept here draws its rows as that same list, from the reply's
    /// rows as they settle.
    func testAReplyKeptHereDrawsItsRowsAsTheOneList() async throws {
        let (model, _) = try await AppModelRunTests.makeModel(behind: FakeRunHub(frames: []))
        let live = LiveReply(conversationID: UUID(), continuingMessageID: nil)
        let events: [ChatEvent] = [
            .tool("Read File: Cargo.lock"), .toolCalled(ToolExchange(callID: "c1", name: "read", arguments: "{}")),
            .toolEnded("c1"), .toolAnswered(callID: "c1", text: "version = 3", failed: false, duration: "3ms"),
            .tool("List Dir"),
        ]
        for event in events {
            model.apply(event, to: live)
        }
        XCTAssertEqual(Self.shown(live.rows), ["0 Read File: Cargo.lock | done | 3ms", "1 List Dir | running | -"])
        XCTAssertEqual(list(in: LiveReplyRow(live: live).body), live.rows)
    }
}
