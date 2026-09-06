import XCTest

@testable import GGChatCore

final class SSEParserTests: XCTestCase {
    func testRealGGLibStreamParsesToEventsAndDone() throws {
        let bytes = try Fixtures.data("gglib-stream-reasoning.sse")
        var parser = SSEParser()
        var items = parser.feed(bytes)
        items += parser.finish()
        XCTAssertEqual(items.last, .done)
        let events = items.dropLast()
        XCTAssertGreaterThan(events.count, 20)
        for case .event(let event) in events {
            XCTAssertTrue(event.data.hasPrefix("{"), "every data line is a JSON object")
        }
    }

    func testFeedingOneByteAtATimeGivesTheSameItems() throws {
        let bytes = try Fixtures.data("gglib-stream-reasoning.sse")
        var whole = SSEParser()
        let expected = whole.feed(bytes) + whole.finish()
        var parser = SSEParser()
        var items: [SSEItem] = []
        for byte in bytes {
            items += parser.feed([byte])
        }
        items += parser.finish()
        XCTAssertEqual(items, expected)
    }

    func testCRLFAndMultiLineDataAndComments() {
        var parser = SSEParser()
        let input = ": ping\r\nevent: tick\r\ndata: a\r\ndata: b\r\n\r\ndata: c\n\n"
        let items = parser.feed(Array(input.utf8))
        XCTAssertEqual(
            items,
            [
                .event(SSEEvent(event: "tick", data: "a\nb")),
                .event(SSEEvent(data: "c")),
            ])
    }

    func testDataWithoutSpaceAfterColonAndIdPersists() {
        var parser = SSEParser()
        let items = parser.feed(Array("id: 7\ndata:x\n\ndata: y\n\n".utf8))
        XCTAssertEqual(
            items,
            [
                .event(SSEEvent(data: "x", id: "7")),
                .event(SSEEvent(data: "y", id: "7")),
            ])
    }

    func testFinishFlushesAnEventWithoutATrailingBlankLine() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed(Array("data: tail".utf8)), [])
        XCTAssertEqual(parser.finish(), [.event(SSEEvent(data: "tail"))])
    }

    func testDoneSentinel() {
        var parser = SSEParser()
        XCTAssertEqual(parser.feed(Array("data: [DONE]\n\n".utf8)), [.done])
    }

    func testMultiByteCharacterSplitAcrossFeeds() {
        var parser = SSEParser()
        let bytes = Array("data: héllo\n\n".utf8)
        let cut = 8
        var items = parser.feed(bytes[..<cut])
        items += parser.feed(bytes[cut...])
        XCTAssertEqual(items, [.event(SSEEvent(data: "héllo"))])
    }
}
