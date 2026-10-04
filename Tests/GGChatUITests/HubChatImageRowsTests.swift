import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A Mac's chat's images on this phone: a row of images alone is drawn with
/// them, each is read from the Mac by id into memory once, and all of them
/// go when the chat is left. None is ever written to the store.
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
}
