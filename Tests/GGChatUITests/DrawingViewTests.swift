import GGChatCore
import UniformTypeIdentifiers
import XCTest

@testable import GGChatUI

/// What is drawn of drawing: the Draw switch, and under a reply being
/// written the line, the bar and the latest look at its picture, in the
/// spinner's place.
@MainActor
final class DrawingViewTests: XCTestCase {
    private static let step = ToolProgress(callID: "c1", stage: .sampling, pass: 1, done: 4, total: 20)

    /// The names of the views a view is built from that start with one of
    /// `names`, in the order it draws them. A view found is not looked into.
    private func drawn(_ names: [String], in value: Any, depth: Int = 0) -> [String] {
        let name = String(describing: type(of: value))
        if let found = names.first(where: name.hasPrefix) { return [found] }
        guard depth < 40 else { return [] }
        return Mirror(reflecting: value).children.flatMap { drawn(names, in: $0.value, depth: depth + 1) }
    }

    /// The switch says its state without colour: the brush filled while on
    /// and its outline while off, with "On" or "Off" to hear. A hub that
    /// cannot draw keeps it showing off whatever the draft holds, says
    /// "Unavailable", and a press says why and turns nothing on.
    func testTheDrawSwitchSaysItsStateAndAPressSaysWhyItCannotDraw() {
        XCTAssertEqual(DrawToggle.symbol(isOn: true), "paintbrush.pointed.fill")
        XCTAssertEqual(DrawToggle.symbol(isOn: false), "paintbrush.pointed")
        XCTAssertEqual(DrawToggle.value(isOn: true, refusal: nil), "On")
        XCTAssertEqual(DrawToggle.value(isOn: false, refusal: nil), "Off")
        XCTAssertEqual(DrawToggle.press(isOn: false, refusal: nil), .set(true))
        XCTAssertEqual(DrawToggle.press(isOn: true, refusal: nil), .set(false))
        XCTAssertTrue(DrawToggle.shows(on: true, refusal: nil))
        XCTAssertFalse(DrawToggle.shows(on: false, refusal: nil))

        let why = "home cannot draw: there is no image model"
        for held in [true, false] {
            XCTAssertFalse(DrawToggle.shows(on: held, refusal: why))
            XCTAssertEqual(DrawToggle.value(isOn: held, refusal: why), "Unavailable")
            XCTAssertEqual(DrawToggle.press(isOn: held, refusal: why), .say(why))
        }
    }

    /// A Mac's reply with no words shows the spinner until a picture is
    /// being drawn or waited for, then the work in its place; the spinner is
    /// back once the tool has ended with no words yet. With words, the work
    /// is drawn under them, and the picture made under both.
    func testAMacsReplyDrawsTheWorkInPlaceOfTheSpinner() {
        let names = ["ProgressView", "ToolWorkView", "MarkdownBlocksView", "MessageImages"]
        let reply = HubLiveReply(providerID: UUID(), chatID: 12, runID: "r", question: nil)
        func rows() -> [String] { drawn(names, in: HubLiveReplyRows(reply: reply, rows: .read([])).body) }
        XCTAssertEqual(rows(), ["ProgressView"])

        reply.apply(.waiting(RunWait(reason: .imageRender, step: 3, total: 20, position: 1)))
        XCTAssertEqual(rows(), ["MarkdownBlocksView", "ToolWorkView"])
        reply.apply(.tool("Generate Image"))
        XCTAssertEqual(rows(), ["ProgressView"])
        reply.apply(.toolProgress(Self.step))
        XCTAssertEqual(rows(), ["MarkdownBlocksView", "ToolWorkView"])
        reply.apply(.toolEnded("c1"))
        XCTAssertEqual(rows(), ["ProgressView"])

        reply.apply(.delta("Here it comes."))
        reply.apply(.toolProgress(Self.step))
        XCTAssertEqual(rows(), ["MarkdownBlocksView", "ToolWorkView"])
        reply.apply(.toolEnded("c1"))
        reply.apply(.images([ImageRef(id: "a1", mime: ImageRef.png, width: 8, height: 8)]))
        XCTAssertEqual(rows(), ["MarkdownBlocksView", "MessageImages"])
    }

    /// The work has a bar while the steps are counted, and under it the
    /// latest look when its bytes are a picture, drawn from the frame as it
    /// came, at its own size in pixels, and never from bytes that are not
    /// an image.
    func testTheWorkIsItsLineItsBarAndTheLatestLook() throws {
        let names = ["ProgressView", "Image"]
        func parts(_ work: ToolWork) -> [String] { drawn(names, in: ToolWorkView(work: work).body) }
        var work = ToolWork()
        XCTAssertEqual(parts(work), [])
        work.apply(.waiting(RunWait(reason: .modelLoad)))
        XCTAssertEqual(parts(work), [])
        work.apply(.toolProgress(ToolProgress(callID: "c1", stage: .loading)))
        XCTAssertEqual(parts(work), [], "a bar with no steps to fill it")
        work.apply(.toolProgress(Self.step))
        XCTAssertEqual(parts(work), ["ProgressView"])

        let png = GeneratedImages.encode(GeneratedImages.halves(width: 128, height: 96), as: .png)
        let look = PreviewFrame(callID: "c1", step: 4, total: 20, data: png)
        work.show(look)
        XCTAssertEqual(parts(work), ["ProgressView", "Image"])
        let picture = try XCTUnwrap(ToolWorkView.picture(of: look))
        XCTAssertEqual([picture.width, picture.height], [128, 96])
        XCTAssertEqual(
            ToolWorkView.label(for: look, in: Locale(identifier: "en_GB")), "The picture so far, at step 4 of 20")

        let junk = PreviewFrame(callID: "c1", step: 5, total: 0, data: Data("not a picture".utf8))
        work.show(junk)
        XCTAssertNil(ToolWorkView.picture(of: junk))
        XCTAssertEqual(parts(work), ["ProgressView"])
        XCTAssertEqual(ToolWorkView.label(for: junk, in: Locale(identifier: "en_GB")), "The picture so far")
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

    /// A reply kept on this device shows a line for each tool it calls
    /// while it is read here, and its spinner only while nothing has
    /// arrived and no picture is being drawn, waited for or already made.
    /// Under it the work is drawn while there is some, then the pictures
    /// made, from this device's store and not a hub's memory.
    func testAReplyKeptHereShowsItsToolsAndNoSpinnerWhileAPictureIsDrawn() async throws {
        let hub = FakeRunHub(frames: [[.tool("Generate Image")], [.toolProgress(Self.step)], [.toolEnded("c1")]])
        hub.with { $0.holdAt = 1 }
        let (model, _) = try await DrawingRunTests.makeModel(behind: hub)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        let live = try XCTUnwrap(model.liveReply)
        let names = ["ToolWorkView", "MessageImages"]
        func under() -> [String] { drawn(names, in: LiveReplyWork(live: live).body) }
        XCTAssertTrue(live.awaitsFirstToken)
        XCTAssertEqual(under(), [])
        try await AppModelRunTests.until("the tool") { live.cursor == 1 }
        XCTAssertEqual(live.tools, ["Generate Image"])
        XCTAssertTrue(live.awaitsFirstToken, "a tool's line alone hid the spinner")

        model.apply(.toolProgress(Self.step), to: live)
        XCTAssertFalse(live.awaitsFirstToken, "the spinner turned beside a picture being drawn")
        XCTAssertEqual(under(), ["ToolWorkView"])
        model.apply(.toolEnded("c1"), to: live)
        XCTAssertTrue(live.awaitsFirstToken)
        XCTAssertEqual(under(), [])
        let image = ImageRef(id: "a1", mime: ImageRef.png, width: 8, height: 8)
        model.apply(.images([image]), to: live)
        XCTAssertFalse(live.awaitsFirstToken, "the spinner turned beside a picture already made")
        XCTAssertEqual(under(), ["MessageImages"])
        let made = strip(in: LiveReplyWork(live: live).body)
        XCTAssertEqual(made?.images, [image])
        XCTAssertEqual(made?.fromHub, false, "a kept picture was read from a hub's memory")
        model.stop()
    }
}
