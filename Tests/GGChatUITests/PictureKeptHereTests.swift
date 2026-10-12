import GGChatCore
import XCTest

@testable import GGChatUI

/// Fixing or redoing a picture in a conversation kept on this phone: its
/// bytes are sent from this device's store, the newer picture is kept there
/// on the same reply, and only a PNG on a reply whose one drawing call made
/// it, behind a paired Mac that can draw, is offered at all.
@MainActor
final class PictureKeptHereTests: XCTestCase {
    private typealias Fixture = PictureFixture
    private typealias Runs = AppModelRunTests

    private static let drew = "Drew 1 image, 1024x1024 PNG, with flux-dev in 76 s; the user can see it, you cannot."
    /// A real PNG, 64 by 32, under a reference that says 1024 by 1024.
    private static let png = GeneratedImages.encode(GeneratedImages.halves(width: 64, height: 32), as: .png)
    private static let image = ImageRef(id: ImageRef.id(of: png), mime: ImageRef.png, width: 1024, height: 1024)
    private let keptID = ImageRef.id(of: FakePictures.drawn)

    private struct Here {
        let model: AppModel
        let hub: FakeRunHub
        let config: ProviderConfig
        let reply: Message
    }

    /// A conversation here whose reply drew `image`, behind a Mac that
    /// says `drawing` of itself.
    private func drawnHere(_ drawing: Drawing = Fixture.can, store: any Store = InMemoryStore()) async throws -> Here {
        let call = ToolExchange(
            callID: "call_1", name: "builtin:generate_image", arguments: #"{"prompt":"a red fox in snow"}"#)
        let hub = FakeRunHub(frames: [
            [.tool("Generate Image"), .toolCalled(call)],
            [.toolEnded("call_1"), .toolAnswered(callID: "call_1", text: Self.drew), .images([Self.image])],
            [.delta("A fox.")],
        ])
        hub.with { $0.images[Self.image.id] = Self.png }
        let (model, config) = try await DrawingRunTests.makeModel(behind: hub, drawing: drawing, store: store)
        XCTAssertTrue(model.send("a fox in snow", images: [], draws: true))
        try await Runs.until("the reply") { Runs.settled(model) && model.selectedConversation?.messages.count == 2 }
        return Here(model: model, hub: hub, config: config, reply: try Runs.last(model))
    }

    /// A conversation kept here sends its picture's bytes from this
    /// device's store, with a mask the size those bytes decode to, and
    /// keeps the newer picture in that store, named on the same reply after
    /// the one it came from, through a reopening. Until Keep the store
    /// holds nothing of it.
    func testAConversationHereKeepsTheNewerPictureOnItsReply() async throws {
        let store = InMemoryStore()
        let here = try await drawnHere(store: store)
        let (model, hub, reply) = (here.model, here.hub, here.reply)
        XCTAssertEqual(reply.images, [Self.image])
        XCTAssertEqual(model.drawnPrompt(of: Self.image, in: reply.id, fromHub: false), "a red fox in snow")
        let editing = try XCTUnwrap(model.pictureEditing(of: Self.image, in: reply.id, fromHub: false))
        XCTAssertEqual(editing.words, "a red fox in snow")
        XCTAssertEqual(editing.size, CGSize(width: 64, height: 32), "the mask would be the reference's size")
        XCTAssertNil(editing.model)
        Fixture.brush(editing)
        await editing.ask()?.value
        let sent = try XCTUnwrap(hub.pictures.with(\.asked).first)
        XCTAssertEqual(sent.image, Self.png)
        let mask = try XCTUnwrap(PictureMask.size(of: try XCTUnwrap(sent.mask)))
        XCTAssertEqual([mask.width, mask.height], [64, 32])
        XCTAssertEqual(editing.phase, .drawn(FakePictures.drawn))
        XCTAssertNil(try store.loadImage(id: keptID), "a picture not kept was stored")
        XCTAssertEqual(try Runs.last(model).images, [Self.image])

        await editing.keep()?.value
        XCTAssertTrue(editing.isKept)
        let newer = ImageRef(id: keptID, mime: ImageRef.png, width: 1024, height: 1024)
        XCTAssertEqual(try Runs.last(model).images, [Self.image, newer])
        XCTAssertEqual(try store.loadImage(id: keptID), FakePictures.drawn)
        XCTAssertEqual(try store.loadConversations().first?.messages.last?.images, [Self.image, newer])
        XCTAssertEqual(model.drawnPrompt(of: newer, in: reply.id, fromHub: false), "a red fox in snow")
        XCTAssertEqual(try Runs.last(model).exchanges, reply.exchanges)
    }

    /// The image model starts at the one the conversation already draws
    /// with, and the request names it.
    func testAConversationHereStartsAtItsOwnImageModel() async throws {
        let here = try await drawnHere(Fixture.lists)
        var conversation = try XCTUnwrap(here.model.selectedConversation)
        conversation.imageModelID = 2
        here.model.update(conversation)
        let editing = try XCTUnwrap(here.model.pictureEditing(of: Self.image, in: here.reply.id, fromHub: false))
        XCTAssertEqual(editing.model, 2)
        XCTAssertEqual(editing.menu.drawsWith, "z-image")
        editing.choose(.redo)
        await editing.ask()?.value
        XCTAssertEqual(here.hub.pictures.with(\.asked).last?.model, 2)
    }

    /// In a conversation kept here a picture is offered on the reply whose
    /// drawing call made it: not a question's own image, not a picture the
    /// reply does not hold, not one that is not a PNG, and none while its
    /// Mac cannot draw or is not a paired one.
    func testOnlyAReplysDrawnPictureIsOfferedInAConversationKeptHere() async throws {
        let here = try await drawnHere()
        let (model, config, reply) = (here.model, here.config, here.reply)
        let question = try XCTUnwrap(model.selectedConversation?.messages.first)
        let other = ImageRef(id: "other", mime: ImageRef.png, width: 8, height: 8)
        XCTAssertNotNil(model.drawnPrompt(of: Self.image, in: reply.id, fromHub: false))
        XCTAssertNil(model.drawnPrompt(of: Self.image, in: question.id, fromHub: false))
        XCTAssertNil(model.drawnPrompt(of: Self.image, in: nil, fromHub: false))
        XCTAssertNil(model.drawnPrompt(of: other, in: reply.id, fromHub: false))
        XCTAssertNil(model.drawnPrompt(of: Self.image, in: reply.id, fromHub: true), "a Mac's chat that is not open")

        var conversation = try XCTUnwrap(model.selectedConversation)
        let photo = ImageRef(id: Self.image.id, mime: ImageRef.jpeg, width: 1024, height: 1024)
        conversation.messages[1].images = [photo]
        model.update(conversation)
        XCTAssertNil(model.drawnPrompt(of: photo, in: reply.id, fromHub: false), "a picture that is not a PNG")
        XCTAssertNil(model.pictureEditing(of: photo, in: reply.id, fromHub: false))
        conversation.messages[1].images = reply.images
        conversation.messages[1].exchanges = []
        model.update(conversation)
        XCTAssertNil(model.drawnPrompt(of: Self.image, in: reply.id, fromHub: false), "a reply with no drawing call")
        conversation.messages[1].exchanges = reply.exchanges
        model.update(conversation)
        XCTAssertNotNil(model.drawnPrompt(of: Self.image, in: reply.id, fromHub: false))

        model.drawings[config.id] = Drawing(available: false)
        XCTAssertNil(model.drawnPrompt(of: Self.image, in: reply.id, fromHub: false))
        XCTAssertNil(model.pictureEditing(of: Self.image, in: reply.id, fromHub: false))

        let direct = FakeRunHub(frames: [])
        let (byAddress, _) = try await Runs.makeModel(behind: direct, direct: true)
        var kept = try XCTUnwrap(byAddress.selectedConversation)
        kept.messages = conversation.messages
        byAddress.update(kept)
        byAddress.drawings[try XCTUnwrap(kept.providerID)] = Fixture.can
        XCTAssertNil(byAddress.drawnPrompt(of: Self.image, in: reply.id, fromHub: false), "a gglib reached by address")
    }
}
