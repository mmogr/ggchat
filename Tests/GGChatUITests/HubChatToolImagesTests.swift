import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// The images a tool makes while a Mac writes a reply this phone is reading:
/// kept on the reply in the order they came, by reference, and drawn under
/// its text from the Mac's bytes, with words or without.
@MainActor
final class HubChatToolImagesTests: XCTestCase {
    private func ref(_ id: String) -> ImageRef {
        ImageRef(id: id, mime: ImageRef.png, width: 640, height: 480)
    }

    private func reply() -> HubLiveReply {
        HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: nil)
    }

    /// Each tool's images join the reply's in order, across two tool calls,
    /// and nothing else of the reply moves.
    func testAToolsImagesJoinTheReplyInOrderAcrossToolCalls() {
        let reply = reply()
        let (first, second, third) = (ref("a1"), ref("b2"), ref("c3"))
        reply.apply(.tool("Plot Chart: build times"))
        reply.apply(.images([first]))
        reply.apply(.tool("Plot Chart: test times"))
        reply.apply(.images([second, third]))
        reply.apply(.delta("Two charts."))
        XCTAssertEqual(reply.made, [first, second, third])
        XCTAssertEqual(reply.tools, ["Plot Chart: build times", "Plot Chart: test times"])
        XCTAssertEqual(reply.content, "Two charts.")
    }

    /// The `MessageImages` a view is built from, if it holds one.
    private func strip(in value: Any, depth: Int = 0) -> MessageImages? {
        if let found = value as? MessageImages { return found }
        guard depth < 40 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = strip(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    /// The reply's images are drawn as the Mac's, read from it by id, both
    /// while the reply has no words yet and once it has them; a reply whose
    /// tools made none draws no strip.
    func testTheImagesAToolMadeAreDrawnAsTheMacs() {
        let reply = reply()
        XCTAssertNil(strip(in: HubLiveReplyRows(reply: reply, rows: .read([])).body), "a strip with nothing in it")
        reply.apply(.images([ref("a1")]))
        for words in ["", "A chart."] {
            reply.apply(.delta(words))
            let drawn = strip(in: HubLiveReplyRows(reply: reply, rows: .read([])).body)
            XCTAssertEqual(drawn?.images, [ref("a1")], "with the words \"\(words)\"")
            XCTAssertEqual(drawn?.fromHub, true, "the images were read from this phone's store")
        }
    }
}
