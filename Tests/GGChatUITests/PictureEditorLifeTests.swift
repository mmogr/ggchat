import GGChatCore
import XCTest

@testable import GGChatUI

/// What an editor left open has to live through: the phone locked and its
/// pipe dialled again at another address, the picture's bytes let go by
/// the chat, a reference that says another size than the bytes, and the row
/// that opened it drawn again.
@MainActor
final class PictureEditorLifeTests: XCTestCase {
    private typealias Fixture = PictureFixture
    private typealias Runs = AppModelRunTests

    /// Puts another Mac where `config`'s pipe answers, as a pipe dialled
    /// again does: the same chat and picture, and nothing asked of it yet.
    private func replace(_ scene: Fixture.Scene) throws -> FakeChatsHub {
        let other = FakeChatsHub()
        other.with { state in
            state.chats[12] = Fixture.chat(scene.picture.ref)
            state.images[scene.picture.id] = scene.picture.data
        }
        other.runs.with { $0.drawing = .success(Fixture.can) }
        let session = try XCTUnwrap(scene.model.pipeSessions[scene.config.id])
        scene.model.registry.register(other, at: session.baseURL)
        return other
    }

    /// The Mac is looked up each time it is asked, not once when the
    /// editor opens: a Mac that took its place since draws the picture,
    /// stores it and links it, and the one the editor opened on hears
    /// nothing more.
    func testTheMacIsLookedUpWhenItIsAskedNotWhenTheEditorOpens() async throws {
        let scene = try await Fixture.opened()
        let editing = try Fixture.editing(scene.model, scene.picture)
        let redialled = try replace(scene)
        editing.choose(.redo)
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertEqual(redialled.pictures.with(\.asked).count, 1)
        XCTAssertEqual(scene.hub.pictures.with(\.asked).count, 0, "the Mac the editor opened on was asked")

        let again = try replace(scene)
        await editing.keep()?.value
        XCTAssertTrue(editing.isKept)
        XCTAssertEqual(again.with(\.uploads), [FakePictures.drawn])
        XCTAssertEqual(again.with { $0.kept.count }, 1)
        XCTAssertEqual(redialled.with(\.uploads), [], "the Mac the picture was drawn on was sent it")
        XCTAssertEqual(scene.hub.with(\.uploads), [])
    }

    /// With the pipe hung up, as the background leaves it, a render and a
    /// Keep each say the Mac is unreachable, and the drawn picture is kept
    /// in hand; once the pipe is dialled again, Keep works.
    func testAPipeHungUpAndDialledAgainLosesNoPicture() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, config) = (scene.model, scene.hub, scene.config)
        let editing = try Fixture.editing(model, scene.picture)
        editing.choose(.redo)
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))

        await model.disconnectPipe(for: config.id)
        await editing.keep()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertEqual(editing.keepFailure, "The picture was drawn but could not be kept: home is unreachable.")
        XCTAssertEqual(hub.with(\.uploads), [])

        await model.connectPipe(for: config)
        try await Runs.until("the pipe") { model.hubIsReachable(config.id) }
        await editing.keep()?.value
        XCTAssertTrue(editing.isKept)
        XCTAssertEqual(hub.with(\.uploads), [FakePictures.drawn])
        XCTAssertEqual(hub.with { $0.kept.count }, 1)

        await model.disconnectPipe(for: config.id)
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .failed("home is unreachable."))
        XCTAssertEqual(hub.pictures.with(\.asked).count, 1)
    }

    /// The mask is the size the picture's bytes decode to, whatever its
    /// reference says, and the bytes are the ones held since the editor
    /// opened: the chat letting go of them afterwards costs nothing.
    func testTheMaskIsTheSizeOfThePicturesBytesWhichAreHeldFromOpening() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        let claimed = ImageRef(id: picture.id, mime: ImageRef.png, width: 128, height: 64)
        let editing = try XCTUnwrap(model.pictureEditing(of: claimed, in: nil, fromHub: true))
        XCTAssertEqual(editing.size, CGSize(width: 64, height: 32))
        XCTAssertEqual(editing.brush, 4)
        model.hubImages.removeAll()
        XCTAssertNil(model.hubImages.data(picture.id))
        Fixture.brush(editing)
        await editing.ask()?.value
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        let sent = try XCTUnwrap(hub.pictures.with(\.asked).first)
        XCTAssertEqual(sent.image, picture.data)
        let mask = try XCTUnwrap(PictureMask.size(of: try XCTUnwrap(sent.mask)))
        XCTAssertEqual([mask.width, mask.height], [64, 32])
    }

    /// The image opened whole and its editor are the model's, so a chat
    /// whose rows are replaced under the sheet keeps the picture drawn in
    /// it. Closing the sheet stops a render it left going.
    func testTheEditorIsTheModelsAndOutlivesTheRowThatOpenedIt() async throws {
        let scene = try await Fixture.opened()
        let (model, hub, picture) = (scene.model, scene.hub, scene.picture)
        model.enlarged = EnlargedPicture(image: picture.ref, fromHub: true, owner: nil)
        model.editEnlargedPicture()
        let editing = try XCTUnwrap(model.pictureEditor)
        editing.choose(.redo)
        await editing.ask()?.value

        model.openedHubChat?.state = .unavailable("home no longer has this chat.")
        XCTAssertTrue(model.pictureEditor === editing)
        XCTAssertEqual(model.pictureEditor?.drawn, FakePictures.drawn)
        XCTAssertEqual(model.enlarged?.image, picture.ref)

        hub.pictures.with { $0.holdAt = 0 }
        editing.ask()
        try await Runs.until("the request") { hub.pictures.with(\.asked).count == 2 }
        model.closePictureEditor()
        XCTAssertNil(model.pictureEditor)
        XCTAssertEqual(editing.phase, .idle)
        try await Runs.until("the reader gone") { hub.pictures.with(\.left) == 1 }
    }
}
