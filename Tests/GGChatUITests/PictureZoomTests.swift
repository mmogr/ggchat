import GGChatCore
import XCTest

@testable import GGChatUI

/// A picture opened whole: how far it is enlarged, where it sits, what a
/// double tap shows, and the bytes it offers to share or save.
@MainActor
final class PictureZoomTests: XCTestCase {
    /// A large picture goes on until a pixel is a point across; a small one
    /// still goes four times closer, and one fitted to nothing does not
    /// divide by it.
    func testAPictureIsEnlargedToItsPixelsAndNeverLessThanFourTimes() {
        let fitted = CGSize(width: 320, height: 240)
        XCTAssertEqual(PictureZoom.most(of: CGSize(width: 2560, height: 1920), fitted: fitted), 8)
        XCTAssertEqual(PictureZoom.most(of: CGSize(width: 64, height: 48), fitted: fitted), PictureZoom.least)
        XCTAssertEqual(PictureZoom.most(of: CGSize(width: 64, height: 48), fitted: .zero), PictureZoom.least)
    }

    /// Smaller than the sheet it sits in the middle; larger, or larger one
    /// way, it has no margin that way.
    func testAPictureSmallerThanTheSheetSitsInItsMiddle() {
        let sheet = CGSize(width: 400, height: 600)
        XCTAssertEqual(
            PictureZoom.margins(of: CGSize(width: 400, height: 200), in: sheet), CGSize(width: 0, height: 200))
        XCTAssertEqual(
            PictureZoom.margins(of: CGSize(width: 1000, height: 500), in: sheet), CGSize(width: 0, height: 50))
        XCTAssertEqual(PictureZoom.margins(of: CGSize(width: 1000, height: 1500), in: sheet), .zero)
    }

    /// A double tap shows the part around the finger, two and a half times
    /// closer, and no closer than the picture goes.
    func testADoubleTapShowsThePartAroundTheFinger() {
        let sheet = CGSize(width: 400, height: 600)
        let part = PictureZoom.part(around: CGPoint(x: 100, y: 80), in: sheet, most: 8)
        XCTAssertEqual(part, CGRect(x: 20, y: -40, width: 160, height: 240))
        XCTAssertEqual(
            PictureZoom.part(around: CGPoint(x: 100, y: 80), in: sheet, most: 2).size, CGSize(width: 200, height: 300))
    }

    /// A Mac's chat's picture is offered as the bytes held in memory, under
    /// the kind its reference names, and not at all once the chat let them
    /// go.
    func testAMacsPictureIsOfferedAsTheBytesHeld() async throws {
        let scene = try await PictureFixture.opened()
        let shown = EnlargedPicture(image: scene.picture.ref, fromHub: true, owner: nil)
        XCTAssertEqual(scene.model.file(of: shown), PictureFile(data: scene.picture.data, mime: ImageRef.png))
        scene.model.hubImages.removeAll()
        XCTAssertNil(scene.model.file(of: shown))
    }

    /// A picture kept here is offered as the bytes in this device's store,
    /// and one the store does not have is not offered.
    func testAPictureKeptHereIsOfferedAsTheBytesStored() throws {
        let store = InMemoryStore()
        let model = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink())
        let picture = try PictureFixture.picture()
        let shown = EnlargedPicture(image: picture.ref, fromHub: false, owner: nil)
        XCTAssertNil(model.file(of: shown))
        try store.save(image: picture.ref, data: picture.data)
        XCTAssertEqual(model.file(of: shown), PictureFile(data: picture.data, mime: ImageRef.png))
    }
}
