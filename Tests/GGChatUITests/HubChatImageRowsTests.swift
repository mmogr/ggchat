import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A Mac's chat's images on this phone: a row of images alone is drawn with
/// them, a tool's images under the reply that follows them, each is read
/// from the Mac by id into memory once, and all of them go when the chat is
/// left. None is ever written to the store.
@MainActor
final class HubChatImageRowsTests: XCTestCase {
    /// Chat 12 with a turn of one image alone and a reply to it.
    private func pictured(_ image: DraftImage) -> HubChatOpen {
        HubChatOpen(
            conversation: FakeChatsHub.opened.conversation,
            messages: FakeChatsHub.opened.messages + [
                HubMessage(id: 44, conversationID: 12, role: "user", content: "", createdAt: "f", images: [image.ref]),
                HubMessage(id: 45, conversationID: 12, role: "assistant", content: "A red and a blue.", createdAt: "g"),
            ])
    }

    /// A row of images alone is drawn, with its images; a row with neither
    /// words nor images is still passed over.
    func testARowOfImagesAloneIsDrawnWithItsImages() throws {
        let image = try HubChatImageSendTests.image(width: 64)
        let rows = AppModel.rows(of: pictured(image), at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            rows.map(\.content), ["Why did the build break?", "A dependency moved.", "", "A red and a blue."])
        XCTAssertEqual(rows.map(\.images), [[], [], [image.ref], []])
    }

    /// An image the chat names is read from the Mac by its id into memory,
    /// once, and drawn from there; none is written to the store, and all go
    /// when the chat is left.
    func testTheMacsImagesAreReadIntoMemoryOnceAndGoWithTheChat() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let image = try HubChatImageSendTests.image(width: 64)
        let hub = FakeChatsHub()
        hub.with { state in
            state.chats[12] = pictured(image)
            state.images[image.id] = image.data
        }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        XCTAssertNil(model.hubThumbnail(of: image.ref))

        await model.fetchHubImage(image.ref)
        await model.fetchHubImage(image.ref)
        XCTAssertEqual(hub.with(\.fetches), [image.id], "an image held was read again")
        XCTAssertEqual(model.hubImages.data(image.id), image.data)
        XCTAssertNotNil(model.hubThumbnail(of: image.ref))
        XCTAssertNotNil(model.hubPicture(of: image.ref))
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<ImageRecord>()), 0, "a Mac's image was stored")
        XCTAssertNil(try store.loadImage(id: image.id))

        model.selection = .hub(providerID: config.id, chatID: 9)
        XCTAssertNil(model.hubImages.data(image.id), "an image outlived its chat")
        XCTAssertNil(model.hubThumbnail(of: image.ref))
    }

    /// Bytes that are not the image the id names are not kept, and an image
    /// the Mac does not have is drawn as missing; a read that lands after
    /// its chat was left keeps nothing.
    func testOnlyTheBytesTheIdNamesAreKept() async throws {
        let image = try HubChatImageSendTests.image(width: 64)
        let other = try HubChatImageSendTests.image(width: 96)
        let hub = FakeChatsHub()
        hub.with { $0.images[image.id] = other.data }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        await model.fetchHubImage(image.ref)
        XCTAssertEqual(hub.with(\.fetches), [image.id])
        XCTAssertNil(model.hubImages.data(image.id))
        XCTAssertEqual(model.hubImages.states[image.id], .missing)
        await model.fetchHubImage(other.ref)
        XCTAssertEqual(model.hubImages.states[other.id], .missing)

        hub.with { state in
            state.images[image.id] = image.data
            state.holdsFetches = true
        }
        let late = Task { await model.fetchHubImage(image.ref) }
        try await AppModelRunTests.until("the read asked") { hub.with(\.fetches).count == 3 }
        model.selection = .hub(providerID: config.id, chatID: 9)
        hub.with { $0.holdsFetches = false }
        await late.value
        XCTAssertNil(model.hubImages.data(image.id), "a read for a chat left was kept")
        XCTAssertNil(model.hubImages.states[image.id])
    }

    /// An image this phone sent is drawn from the bytes it holds, and not
    /// read back from the Mac while it holds them; once the chat is left
    /// and opened again, it is read like any other.
    func testAnImageThisPhoneSentIsNotReadBack() async throws {
        let hub = FakeChatsHub()
        hub.runs.with { $0.holdAt = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        let image = try HubChatImageSendTests.image(width: 64)
        model.sendToHubChat("", images: [image])
        try await AppModelRunTests.until("the first frame") { model.openHubReply?.tools.isEmpty == false }
        await model.fetchHubImage(image.ref)
        XCTAssertEqual(model.hubImages.data(image.id), image.data)
        XCTAssertEqual(hub.with(\.fetches), [])
        hub.runs.release()
        try await AppModelRunTests.until("the reply") { model.hubReplies.isEmpty }

        model.selection = .hub(providerID: config.id, chatID: 9)
        model.selection = .hub(providerID: config.id, chatID: 12)
        await model.fetchHubImage(image.ref)
        XCTAssertEqual(hub.with(\.fetches), [image.id])
        XCTAssertEqual(model.hubImages.data(image.id), image.data)
    }

    /// Chat 12 with these rows after its own.
    private func chat(_ rows: [HubMessage]) -> HubChatOpen {
        FakeChatsHub.opened.with(nil, rows: FakeChatsHub.opened.messages + rows)
    }

    /// A row of chat 12, its id and time beside the point here.
    private func row(_ role: String, _ content: String, _ images: [ImageRef]? = nil) -> HubMessage {
        HubMessage(id: 0, conversationID: 12, role: role, content: content, createdAt: "f", images: images)
    }

    /// A tool's images go to the next assistant row that has words, under
    /// its text: after its own images and in the order its tools made them
    /// across two tool rows, without the words the model read. A wordless
    /// reply with images of its own keeps only those, and a tool's row
    /// without images is still passed over.
    func testAToolsImagesGoUnderTheTextOfTheReplyThatFollows() throws {
        let (first, second) = (try HubChatImageSendTests.image(width: 64), try HubChatImageSendTests.image(width: 96))
        let (lone, own) = (try HubChatImageSendTests.image(width: 128), try HubChatImageSendTests.image(width: 160))
        let rows = AppModel.rows(
            of: chat([
                row("user", "Chart both."), row("assistant", ""), row("tool", "[image 64x32 PNG stored]", [first.ref]),
                row("assistant", "", [lone.ref]), row("tool", "[image 96x32 PNG stored]", [second.ref]),
                row("tool", "no image"), row("assistant", "Here they are.", [own.ref]),
            ]),
            at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            rows.map(\.content),
            ["Why did the build break?", "A dependency moved.", "Chart both.", "", "Here they are."])
        XCTAssertEqual(rows.map(\.role), [.user, .assistant, .user, .assistant, .assistant])
        XCTAssertEqual(rows.map(\.images), [[], [], [], [lone.ref], [own.ref, first.ref, second.ref]])
    }

    /// A reply that ended after its tool, with no words after it, is the
    /// tool's images alone, before the next question and at the chat's end.
    func testAReplyThatEndedAfterItsToolIsItsImagesAlone() throws {
        let (first, second) = (try HubChatImageSendTests.image(width: 64), try HubChatImageSendTests.image(width: 96))
        let rows = AppModel.rows(
            of: chat([
                row("user", "Chart it."), row("tool", "", [first.ref]), row("user", "Again."),
                row("tool", "", [second.ref]),
            ]),
            at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            rows.suffix(4).map(\.content), ["Chart it.", "", "Again.", ""])
        XCTAssertEqual(rows.suffix(4).map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(rows.suffix(4).map(\.images), [[], [first.ref], [], [second.ref]])
    }

    /// The images a tool makes while the reply is read are read from the
    /// Mac by id, the bytes it holds kept, and once the Mac's rows take the
    /// reply's place the same image on its tool row is not read again.
    func testAToolsImagesAreReadFromTheMacByIdOnceFromReplyToRow() async throws {
        let image = try HubChatImageSendTests.image(width: 64)
        let hub = FakeChatsHub(reply: [[.tool("Plot Chart")], [.images([image.ref])], [.delta("Here it is.")]])
        hub.with { $0.images[image.id] = image.data }
        hub.runs.with { $0.holdAt = 3 }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        model.sendToHubChat("Chart it.")
        try await AppModelRunTests.until("the reply") { model.openHubReply?.content == "Here it is." }
        let made = try XCTUnwrap(model.openHubReply?.made)
        XCTAssertEqual(made, [image.ref])
        XCTAssertEqual(hub.with(\.fetches), [], "an image was read before it was drawn")

        await model.fetchHubImage(try XCTUnwrap(made.first))
        XCTAssertEqual(hub.with(\.fetches), [image.id])
        XCTAssertEqual(model.hubImages.data(image.id), image.data)

        let saved = FakeChatsHub.opened.with(
            nil,
            rows: FakeChatsHub.opened.messages + [
                HubMessage(id: 44, conversationID: 12, role: "user", content: "Chart it.", createdAt: "f"),
                HubMessage(id: 45, conversationID: 12, role: "tool", content: "", createdAt: "g", images: [image.ref]),
                HubMessage(id: 46, conversationID: 12, role: "assistant", content: "Here it is.", createdAt: "h"),
            ])
        hub.with { $0.chats[12] = saved }
        hub.runs.release()
        try await AppModelRunTests.until("the Mac's rows") { model.hubReplies.isEmpty }
        guard case .read(let rows)? = model.openedHubChat?.state else { return XCTFail("no rows") }
        XCTAssertEqual(rows.suffix(2).map(\.content), ["Chart it.", "Here it is."])
        XCTAssertEqual(rows.suffix(2).map(\.images), [[], [image.ref]])
        await model.fetchHubImage(image.ref)
        XCTAssertEqual(hub.with(\.fetches), [image.id], "an image held was read again")
    }
}
