import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// Keeping a picture drawn again in a Mac's chat, and where fixing one is
/// offered there: the Mac keeps it beside the one it came from, a Keep that
/// fails loses nothing, and only a picture the drawing tool made, on a Mac
/// that can draw, is offered at all.
@MainActor
final class PictureKeepingTests: XCTestCase {
    private typealias Fixture = PictureFixture
    private typealias Runs = AppModelRunTests

    private let keptID = ImageRef.id(of: FakePictures.drawn)

    /// The images of the last reply the chat open shows.
    private func shown(_ model: AppModel) -> [String] {
        guard case .read(let rows)? = model.openedHubChat?.state else { return [] }
        return rows.last?.images.map(\.id) ?? []
    }

    /// An editor on the Mac's chat's picture, with a picture drawn again.
    private func drawn(
        _ drawing: Drawing = Fixture.can, store: any Store = InMemoryStore()
    ) async throws -> (editing: PictureEditing, scene: Fixture.Scene) {
        let scene = try await Fixture.opened(drawing, store: store)
        let editing = try Fixture.editing(scene.model, scene.picture)
        editing.choose(.redo)
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        return (editing, scene)
    }

    /// Keep sends the picture to the Mac's store, then names it and the
    /// one it came from to the chat's `pictures`, and the chat, read again,
    /// shows it last on that reply. It is drawn from the bytes held here,
    /// can be fixed in its turn, and nothing of it is written to the phone.
    func testKeepStoresThePictureThenLinksItAndTheChatShowsItLast() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let (editing, scene) = try await drawn(store: store)
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        XCTAssertEqual(shown(model), [picture.id])
        let keep = try XCTUnwrap(editing.keep())
        XCTAssertEqual(editing.phase, .keeping(FakePictures.drawn))
        XCTAssertTrue(editing.holdsWork)
        XCTAssertNil(editing.ask(), "a picture was drawn again while one was being kept")
        await keep.value
        XCTAssertTrue(editing.isKept)
        XCTAssertEqual(editing.phase, .idle)
        XCTAssertNil(editing.keepFailure)
        XCTAssertEqual(hub.with(\.uploads), [FakePictures.drawn])
        XCTAssertEqual(hub.with { $0.kept.map(\.chatID) }, [12])
        XCTAssertEqual(hub.with { $0.kept.map(\.picture) }, [KeptPicture(from: picture.id, image: keptID)])

        try await Runs.until("the chat read again") { self.shown(model) == [picture.id, self.keptID] }
        XCTAssertEqual(model.hubImages.data(keptID), FakePictures.drawn)
        let newer = ImageRef(id: keptID, mime: ImageRef.png, width: 64, height: 32)
        await model.fetchHubImage(newer)
        XCTAssertEqual(hub.with(\.fetches), [picture.id], "the kept picture was read back")
        XCTAssertEqual(model.drawnPrompt(of: newer, in: nil, fromHub: true), Fixture.prompt)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ImageRecord>()), 0, "a Mac's picture was stored")
    }

    /// A Keep the Mac refuses leaves the drawn picture where it was, with
    /// why, and Keep works a second time: the picture already in the Mac's
    /// store is not sent again. One whose upload failed is sent again.
    func testAFailedKeepLeavesThePictureAndKeepWorksASecondTime() async throws {
        let (editing, scene) = try await drawn()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        hub.with { $0.keepFailure = .server(status: 404, code: "conversation_not_found", message: "no such chat") }
        await editing.keep()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn), "a failed keep lost the picture")
        XCTAssertEqual(editing.keepFailure, "The picture was drawn but could not be kept: no such chat")
        XCTAssertEqual(PictureEditor.failure(of: editing), editing.keepFailure)
        XCTAssertFalse(editing.isKept)
        XCTAssertTrue(editing.holdsWork)
        XCTAssertEqual(shown(model), [picture.id])

        hub.with { $0.keepFailure = nil }
        await editing.keep()?.value
        XCTAssertTrue(editing.isKept)
        XCTAssertNil(editing.keepFailure)
        XCTAssertEqual(hub.with(\.uploads), [FakePictures.drawn], "the picture was sent to the store twice")
        XCTAssertEqual(hub.with { $0.kept.count }, 2)
        try await Runs.until("the chat read again") { self.shown(model) == [picture.id, self.keptID] }

        let (again, second) = try await drawn()
        let other = second.hub
        other.with { $0.uploadFailure = .refused(.server(status: 413, code: "image_too_large", message: "too large")) }
        await again.keep()?.value
        XCTAssertEqual(again.phase, .drawn(FakePictures.drawn))
        XCTAssertEqual(again.keepFailure, "The picture was drawn but could not be kept: too large")
        XCTAssertEqual(other.with { $0.kept.count }, 0, "a picture the Mac does not hold was linked")
        other.with { $0.uploadFailure = nil }
        await again.keep()?.value
        XCTAssertTrue(again.isKept)
        XCTAssertEqual(other.with(\.uploads).count, 2)
    }

    /// Once the Mac has kept the picture, a read of the chat that fails is
    /// not a failed Keep: the editor closes, and nothing is taken back.
    func testAReadThatFailsAfterAKeepIsNotAFailedKeep() async throws {
        let (editing, scene) = try await drawn()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        hub.with { $0.openFailure = .dropped(nil) }
        await editing.keep()?.value
        XCTAssertTrue(editing.isKept)
        XCTAssertNil(editing.keepFailure)
        XCTAssertEqual(editing.phase, .idle)
        try await Runs.until("the read") { hub.with(\.opens).count == 2 && model.hubReading == nil }
        XCTAssertEqual(shown(model), [picture.id], "the rows on screen were dropped")
        XCTAssertEqual(hub.with { $0.kept.count }, 1)
    }

    /// The image model starts at the one the chat already draws with, and
    /// is sent with the picture; a chat that chose none starts at the Mac's
    /// own and sends none, and so does a choice the Mac lists without its
    /// files. There is a menu only where two or more can draw. A Mac that
    /// cannot draw until a model is named, and lists one that can, starts
    /// at that one and names it, since there is no menu to pick it from.
    /// A Mac with several image models and no default draws for none until
    /// one is named: the editor asks for the choice first, and lists no
    /// "Default" row to pick.
    func testAMacWithNoDefaultIsAskedWhichImageModelFirst() {
        let waiting = Drawing(
            available: false, reason: "several image models and no default",
            models: [
                ImageModelRow(id: 7, name: "z-image", family: "z-image"),
                ImageModelRow(id: 9, name: "qwen-image", family: "qwen-image-2.1"),
            ])
        let ref = ImageRef(id: String(repeating: "a", count: 64), mime: ImageRef.png, width: 64, height: 32)
        let work = PictureWork(
            bytes: { nil }, render: { _ in AsyncStream { $0.finish() } }, store: { _ in ref }, join: { _, _ in })
        let editing = PictureEditing(picture: ref, prompt: "a fox", drawing: waiting, chosen: nil, work: work)
        editing.choose(.redo)

        XCTAssertNil(editing.model)
        XCTAssertEqual(editing.menu.rows.map { $0.model }, [7, 9])
        XCTAssertEqual(editing.blocked, "Choose an image model first.")

        editing.model = 9
        XCTAssertNil(editing.blocked)
    }

    func testTheImageModelStartsAtTheChatsOwnChoice() async throws {
        let scene = try await Fixture.opened(Fixture.lists)
        let (model, hub, config, picture) = (scene.model, scene.hub, scene.config, scene.picture)
        let plain = try Fixture.editing(model, picture)
        XCTAssertNil(plain.model)
        XCTAssertTrue(plain.menu.isOffered)
        XCTAssertEqual(plain.menu.rows.map(\.model), [nil, 1, 2, 3])
        XCTAssertEqual(plain.menu.rows.map(\.enabled), [true, true, true, false])
        XCTAssertEqual(plain.menu.drawsWith, "flux-dev")

        await model.setHubImageModel(2)?.value
        let chosen = try Fixture.editing(model, picture)
        XCTAssertEqual(chosen.model, 2)
        XCTAssertEqual(chosen.menu.drawsWith, "z-image")
        chosen.choose(.redo)
        await chosen.ask()?.value
        XCTAssertEqual(hub.pictures.with(\.asked).last?.model, 2)
        plain.choose(.redo)
        await plain.ask()?.value
        XCTAssertNil(hub.pictures.with(\.asked).last?.model)

        let work = PictureWork(
            bytes: { nil }, render: { _ in AsyncStream { $0.finish() } }, store: { _ in picture.ref },
            join: { _, _ in })
        let incomplete = PictureEditing(
            picture: picture.ref, prompt: "a fox", drawing: Fixture.lists, chosen: 3, work: work)
        XCTAssertNil(incomplete.model)
        let single = PictureEditing(picture: picture.ref, prompt: "a fox", drawing: Fixture.can, chosen: 2, work: work)
        XCTAssertNil(single.model)
        XCTAssertFalse(single.menu.isOffered)

        let only = Drawing(
            available: false, reason: "no default image model",
            models: [
                ImageModelRow(id: 7, name: "z-image", family: "z-image"),
                ImageModelRow(id: 8, name: "sdxl-base", family: "sdxl", complete: false, missing: ["vae"]),
            ])
        model.drawings[config.id] = only
        await model.setHubImageModel(nil)?.value
        model.drawings[config.id] = only
        let alone = try Fixture.editing(model, picture)
        XCTAssertEqual(alone.model, 7)
        XCTAssertFalse(alone.menu.isOffered)
        alone.choose(.redo)
        await alone.ask()?.value
        XCTAssertEqual(hub.pictures.with(\.asked).last?.model, 7)
        let able = PictureEditing(picture: picture.ref, prompt: "a fox", drawing: Fixture.can, chosen: nil, work: work)
        XCTAssertNil(able.model, "a Mac that can draw was named a model nobody chose")
    }

    /// In a Mac's chat only a picture the drawing tool made is offered: not
    /// an image a person sent, and none while the Mac cannot draw or is out
    /// of reach.
    func testOnlyAPictureTheDrawingToolMadeOnAMacThatCanDrawIsOffered() async throws {
        let own = try HubChatImageSendTests.image(width: 96)
        let scene = try await Fixture.opened(asked: own)
        let (model, config, picture) = (scene.model, scene.config, scene.picture)
        XCTAssertEqual(model.drawnPrompt(of: picture.ref, in: nil, fromHub: true), Fixture.prompt)
        XCTAssertNil(model.drawnPrompt(of: own.ref, in: nil, fromHub: true))
        XCTAssertNil(model.pictureEditing(of: own.ref, in: nil, fromHub: true))
        XCTAssertNotNil(model.pictureEditing(of: picture.ref, in: nil, fromHub: true))

        model.drawings[config.id] = Drawing(available: false, code: "drawing_unavailable", reason: "no image model")
        XCTAssertNil(model.drawnPrompt(of: picture.ref, in: nil, fromHub: true))
        let needsAChoice = Drawing(
            available: false, reason: "several image models and no default",
            models: [ImageModelRow(id: 1, name: "a", family: "sdxl"), ImageModelRow(id: 2, name: "b", family: "sdxl")])
        model.drawings[config.id] = needsAChoice
        XCTAssertEqual(model.drawnPrompt(of: picture.ref, in: nil, fromHub: true), Fixture.prompt)
        model.drawings[config.id] = nil
        XCTAssertNil(model.drawnPrompt(of: picture.ref, in: nil, fromHub: true))

        model.drawings[config.id] = Fixture.can
        await model.disconnectPipe(for: config.id)
        XCTAssertNil(model.drawnPrompt(of: picture.ref, in: nil, fromHub: true), "offered with the Mac out of reach")
        XCTAssertNil(model.pictureEditing(of: picture.ref, in: nil, fromHub: true))
    }
}
