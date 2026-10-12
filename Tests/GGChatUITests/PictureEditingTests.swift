import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// Fixing or redoing a picture, from the choices to the picture drawn: what
/// has to be chosen first, what the Mac is sent, the render followed to its
/// end, and that Stop, Discard and Try again keep nothing.
@MainActor
final class PictureEditingTests: XCTestCase {
    private typealias Fixture = PictureFixture

    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// Fix waits for a stroke that paints, and both wait for words, each
    /// saying which; until then nothing is asked of the Mac. Fix starts at
    /// 0.75 and Redo at 0.4, the words start as the picture's own, and the
    /// brush starts at six hundredths of the picture's longer side.
    func testFixWaitsForABrushStrokeAndBothWaitForWords() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        let editing = try Fixture.editing(model, picture)
        XCTAssertEqual(editing.words, Fixture.prompt)
        XCTAssertEqual(editing.mode, .fix)
        XCTAssertEqual(editing.strength, 0.75)
        XCTAssertEqual(editing.size, CGSize(width: 64, height: 32))
        XCTAssertEqual(editing.brush, 4)
        XCTAssertEqual(editing.askTitle, "Fix this part")
        XCTAssertEqual(editing.blocked, "Brush over the part to fix first.")
        XCTAssertNil(editing.ask())

        editing.erasing = true
        editing.begin(at: CGPoint(x: 8, y: 8))
        XCTAssertEqual(editing.blocked, "Brush over the part to fix first.", "rubbing out was taken for brushing")
        editing.erasing = false
        Fixture.brush(editing)
        XCTAssertNil(editing.blocked)
        XCTAssertEqual(editing.strokes.count, 2)
        XCTAssertEqual(editing.strokes.last, MaskStroke(points: [CGPoint(x: 8, y: 8), CGPoint(x: 24, y: 8)], width: 4))
        editing.undo()
        XCTAssertEqual(editing.strokes, [MaskStroke(points: [CGPoint(x: 8, y: 8)], width: 4, erases: true)])
        Fixture.brush(editing)
        editing.clear()
        XCTAssertEqual(editing.strokes, [])
        XCTAssertEqual(editing.blocked, "Brush over the part to fix first.")

        editing.choose(.redo)
        XCTAssertEqual(editing.strength, 0.4)
        XCTAssertEqual(editing.askTitle, "Draw it again")
        XCTAssertNil(editing.blocked)
        editing.words = " \n"
        XCTAssertEqual(editing.blocked, "Say what the picture should show.")
        XCTAssertNil(editing.ask())
        editing.choose(.fix)
        XCTAssertEqual(editing.strength, 0.75)
        XCTAssertEqual(editing.blocked, "Say what the picture should show.")
        XCTAssertEqual(hub.pictures.with(\.asked), [])
        XCTAssertEqual(editing.phase, .idle)
    }

    /// A fix sends the picture's own bytes, the words, the strength and a
    /// mask the picture's size; a redo sends the picture and no mask, even
    /// with strokes left from before.
    func testAFixSendsThePictureWithAMaskItsSizeAndARedoSendsNoMask() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        let editing = try Fixture.editing(model, picture)
        Fixture.brush(editing)
        editing.words = "  a fox with one tail "
        await editing.ask()?.value
        let fix = try XCTUnwrap(hub.pictures.with(\.asked).first)
        XCTAssertEqual(fix.image, picture.data)
        XCTAssertEqual(fix.strength, 0.75)
        XCTAssertNil(fix.model)
        let sent = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(fix)) as? [String: Any]
        XCTAssertEqual(sent?["prompt"] as? String, "a fox with one tail")
        let mask = try XCTUnwrap(fix.mask)
        let size = try XCTUnwrap(PictureMask.size(of: mask))
        XCTAssertEqual([size.width, size.height], [64, 32])
        XCTAssertEqual(mask, PictureMask.png(of: editing.strokes, width: 64, height: 32))

        editing.discard()
        editing.choose(.redo)
        await editing.ask()?.value
        let redo = try XCTUnwrap(hub.pictures.with(\.asked).last)
        XCTAssertEqual(hub.pictures.with(\.asked).count, 2)
        XCTAssertEqual(redo.image, picture.data)
        XCTAssertNil(redo.mask)
        XCTAssertEqual(redo.strength, 0.4)
    }

    /// The render is followed stage by stage, a report with no frame
    /// keeping the frame before it, to the picture drawn; while it is in
    /// hand the editor holds work, and the choices cannot be changed. The
    /// device is kept awake from the render's start to its end, and the
    /// original is no longer held up once another render starts.
    func testARenderIsFollowedToItsPictureAndAFrameIsKeptAcrossAReportWithoutOne() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        var awake: [Bool] = []
        model.keepsAwake = { awake.append($0) }
        let editing = try Fixture.editing(model, picture)
        let frame = Data([7, 7, 7])
        let script: [RedrawEvent] = [
            .progress(RedrawProgress(stage: "loading")),
            .progress(RedrawProgress(stage: "sampling", step: 1, total: 4, frame: frame)),
            .progress(RedrawProgress(stage: "sampling", step: 2, total: 4)),
            .drawn(FakePictures.drawn),
        ]
        hub.pictures.with { state in
            state.script = script
            state.holdAt = 0
        }
        editing.choose(.redo)
        XCTAssertFalse(editing.holdsWork)
        let render = try XCTUnwrap(editing.ask())
        XCTAssertEqual(editing.phase, .drawing(nil))
        XCTAssertEqual(awake, [true])
        XCTAssertTrue(editing.holdsWork)
        XCTAssertFalse(editing.isEditing)
        hub.pictures.with { $0.holdAt = 1 }
        try await until("loading") { editing.phase == .drawing(RedrawProgress(stage: "loading")) }
        hub.pictures.with { $0.holdAt = 3 }
        try await until("the second step") {
            editing.phase == .drawing(RedrawProgress(stage: "sampling", step: 2, total: 4, frame: frame))
        }
        hub.pictures.release()
        await render.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertEqual(editing.drawn, FakePictures.drawn)
        XCTAssertTrue(editing.holdsWork)
        XCTAssertFalse(editing.isEditing)
        XCTAssertEqual(awake, [true, false])

        editing.comparing = true
        hub.pictures.with { $0.script = [.failed("no")] }
        let again = editing.ask()
        XCTAssertFalse(editing.comparing, "the original stayed held up under another render")
        await again?.value
        XCTAssertEqual(awake, [true, false, true, false], "a render that failed left the device awake")
    }

    /// A render that fails says the Mac's own words, and one that ends
    /// with nothing says so; the choices are as they were, and asking
    /// again draws.
    func testAFailureSaysTheMacsWordsAndCanBeAskedAgain() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        let editing = try Fixture.editing(model, picture)
        Fixture.brush(editing)
        hub.pictures.with { $0.script = [.failed("the image model ran out of memory")] }
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .failed("the image model ran out of memory"))
        XCTAssertEqual(PictureEditor.failure(of: editing), "the image model ran out of memory")
        XCTAssertTrue(editing.isEditing)
        XCTAssertFalse(editing.holdsWork)
        XCTAssertEqual(editing.strokes.count, 1)

        hub.pictures.with { $0.script = [] }
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .failed("The render ended without a picture."))

        hub.pictures.with { $0.script = [.drawn(FakePictures.drawn)] }
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertNil(PictureEditor.failure(of: editing))
    }

    /// Stop goes back to choosing and the Mac's render loses its reader;
    /// what that render says afterwards changes nothing. Leaving the
    /// editor stops a render the same way.
    func testStopAndLeavingEndTheRenderAndALateEventChangesNothing() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        var awake: [Bool] = []
        model.keepsAwake = { awake.append($0) }
        let editing = try Fixture.editing(model, picture)
        editing.choose(.redo)
        hub.pictures.with { $0.holdAt = 0 }
        let stopped = try XCTUnwrap(editing.ask())
        try await until("the request") { hub.pictures.with(\.asked).count == 1 }
        editing.stop()
        XCTAssertEqual(editing.phase, .idle)
        XCTAssertEqual(awake, [true, false])
        hub.pictures.release()
        await stopped.value
        try await until("the reader gone") { hub.pictures.with(\.left) == 1 }
        XCTAssertEqual(editing.phase, .idle)
        XCTAssertNil(editing.drawn)

        hub.pictures.with { $0.holdAt = 0 }
        let left = try XCTUnwrap(editing.ask())
        try await until("the second request") { hub.pictures.with(\.asked).count == 2 }
        editing.leave()
        XCTAssertEqual(editing.phase, .idle)
        XCTAssertEqual(awake, [true, false, true, false])
        hub.pictures.release()
        await left.value
        try await until("the second reader gone") { hub.pictures.with(\.left) == 2 }
        XCTAssertEqual(editing.phase, .idle)
    }

    /// A render another replaced is not the one shown: only the newer
    /// one's picture is.
    func testARenderAnotherReplacedIsIgnored() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        let editing = try Fixture.editing(model, picture)
        editing.choose(.redo)
        let first = Data("THE FIRST".utf8)
        hub.pictures.with { state in
            state.script = [.drawn(first)]
            state.holdAt = 0
        }
        let older = try XCTUnwrap(editing.ask())
        try await until("the first request") { hub.pictures.with(\.asked).count == 1 }
        hub.pictures.with { $0.script = [.drawn(FakePictures.drawn)] }
        let newer = try XCTUnwrap(editing.ask())
        try await until("the second request") { hub.pictures.with(\.asked).count == 2 }
        hub.pictures.release()
        await older.value
        await newer.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertEqual(hub.pictures.with(\.left), 1)
    }

    /// Until Keep nothing is sent to the Mac's store or its chat, and
    /// nothing is written here: not by a picture drawn, by Discard, by Try
    /// again or by Stop.
    func testNothingIsStoredOrLinkedByDrawingDiscardTryAgainOrStop() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let scene = try await Fixture.opened(store: store)
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        let editing = try Fixture.editing(model, picture)
        editing.choose(.redo)
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        editing.discard()
        XCTAssertEqual(editing.phase, .idle)
        XCTAssertNil(editing.keep(), "a discarded picture could be kept")

        await editing.ask()?.value
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertEqual(hub.pictures.with(\.asked).count, 3)
        hub.pictures.with { $0.holdAt = 0 }
        let render = editing.ask()
        editing.stop()
        hub.pictures.release()
        await render?.value
        XCTAssertNil(editing.keep(), "a stopped render could be kept")

        XCTAssertEqual(hub.with(\.uploads), [])
        XCTAssertEqual(hub.with { $0.kept.count }, 0)
        XCTAssertEqual(hub.with(\.opens), [12], "the chat was read again with nothing kept")
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ImageRecord>()), 0)
        XCTAssertFalse(editing.isKept)
    }
}
