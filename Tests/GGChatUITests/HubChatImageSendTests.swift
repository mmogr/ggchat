import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// A turn to a Mac's chat with images: each is sent to the Mac first and
/// the turn names them by id, a turn may be images alone, a turn put again
/// sends them again only when the Mac no longer holds them, and a turn that
/// goes nowhere gives back its text and images. Nothing is written to the
/// phone's store.
@MainActor
final class HubChatImageSendTests: XCTestCase {
    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    static func image(width: Int) throws -> DraftImage {
        try ImageDownscale().prepare(
            GeneratedImages.encode(GeneratedImages.halves(width: width, height: 32), as: .png))
    }

    private func imageRecords(_ store: SwiftDataStore) throws -> Int {
        try store.context.fetchCount(FetchDescriptor<ImageRecord>())
    }

    /// Each image is sent as its bytes, in order, then the turn is put
    /// naming them by the ids the Mac answered; nothing reaches the store.
    func testEachImageIsSentThenTheTurnNamesThem() async throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let hub = FakeChatsHub()
        let (model, _) = try await HubChatContinueTests.opened(hub, store: store)
        let (first, second) = (try Self.image(width: 64), try Self.image(width: 96))

        model.sendToHubChat("What are these?", images: [first, second])
        try await until("the reply") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.with(\.uploads), [first.data, second.data])
        XCTAssertEqual(
            hub.with(\.turns).map(\.turn),
            [HubTurn(conversationID: 12, content: "What are these?", images: [first.id, second.id])])
        XCTAssertEqual(try imageRecords(store), 0, "a Mac's turn's image was written to the store")
        XCTAssertNil(try store.loadImage(id: first.id))
    }

    /// A turn may be images alone: its text is empty. A turn with neither
    /// is not sent.
    func testATurnOfImagesAloneIsSentAndAnEmptyOneIsNot() async throws {
        let hub = FakeChatsHub()
        let (model, _) = try await HubChatContinueTests.opened(hub)
        XCTAssertNil(model.sendToHubChat("  \n", images: []))
        XCTAssertEqual(hub.with(\.turns).count, 0)
        let image = try Self.image(width: 64)
        await model.sendToHubChat("", images: [image])?.value
        XCTAssertEqual(hub.with(\.turns).map(\.turn), [HubTurn(conversationID: 12, content: "", images: [image.id])])
    }

    /// A Mac that no longer holds an image the turn names refused it and
    /// started nothing: the image is sent again from the bytes held here,
    /// and the turn put again under the same id, then read.
    func testAnImageTheMacLetGoIsSentAgainAndTheTurnPutUnderTheSameID() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.forgetsUploads = 1 }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        let image = try Self.image(width: 64)
        model.sendToHubChat("And this?", images: [image])
        try await until("the reply") { model.hubReplies.isEmpty }
        XCTAssertEqual(hub.with(\.uploads), [image.data, image.data])
        let turns = hub.with(\.turns)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(Set(turns.map(\.runID)).count, 1, "the turn was put again under another id")
        XCTAssertEqual(turns.last?.turn.images, [image.id])
        XCTAssertEqual(hub.runs.with { $0.reads.count }, 1)
        XCTAssertNil(model.openedHubChat?.notice)
    }

    /// A Mac that keeps none of the images is sent each of them once more,
    /// and the turn put once more under the same id; refused again, it says
    /// so and gives back the text and the images.
    func testAMacThatKeepsNoImageIsSentThemOnceMoreAndThenSaysSo() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.forgetsUploads = 100 }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        let (first, second) = (try Self.image(width: 64), try Self.image(width: 96))
        await model.sendToHubChat("And these?", images: [first, second])?.value
        XCTAssertEqual(hub.with(\.uploads), [first.data, second.data, first.data, second.data])
        let turns = hub.with(\.turns)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(Set(turns.map(\.runID)).count, 1, "the turn was put again under another id")
        XCTAssertEqual(model.openedHubChat?.notice, "home no longer has an image this chat carries.")
        let back = try XCTUnwrap(model.takeUnsentHubDraft())
        XCTAssertEqual(back.text, "And these?")
        XCTAssertEqual(back.images.map(\.data), [first.data, second.data])
        XCTAssertEqual(hub.runs.with { $0.reads.count }, 0)
    }

    /// A turn of text alone refused because the Mac no longer has an image
    /// the chat names is not put again or sent any image: it says so and
    /// gives back its text.
    func testATextTurnRefusedForAnImageIsNotSentImagesAndSaysSo() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.turnFailure = .imageGone }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        await model.sendToHubChat("And now?")?.value
        XCTAssertEqual(hub.with(\.uploads).count, 0)
        XCTAssertEqual(hub.with(\.turns).map(\.turn), [HubTurn(conversationID: 12, content: "And now?")])
        XCTAssertEqual(model.openedHubChat?.notice, "home no longer has an image this chat carries.")
        let back = try XCTUnwrap(model.takeUnsentHubDraft())
        XCTAssertEqual(back.text, "And now?")
        XCTAssertEqual(back.images.count, 0)
    }

    /// A turn whose answer was lost is put again with its images, which the
    /// Mac still holds, so they are not sent again.
    func testALostTurnIsPutAgainWithItsImagesWithoutSendingThemAgain() async throws {
        let hub = FakeChatsHub()
        hub.with { $0.turnsDropped = 1 }
        let (model, config) = try await HubChatContinueTests.opened(hub)
        let image = try Self.image(width: 64)
        model.sendToHubChat("And this?", images: [image])
        try await until("the dropped send") { hub.with(\.dropped).count == 1 && model.openHubReply?.reading == nil }
        model.hubPipeCameUp(config.id)
        try await until("the turn put again") { hub.with(\.turns).count == 1 }
        XCTAssertEqual(hub.with(\.turns).first?.turn.images, [image.id])
        XCTAssertEqual(hub.with(\.turns).first?.runID, hub.with(\.dropped).first)
        XCTAssertEqual(hub.with(\.uploads).count, 1)
    }

    /// A turn the Mac refuses gives back its text and its images, bytes and
    /// all, on screen at once, and one refused off screen when its chat is
    /// next opened.
    func testARefusedTurnGivesBackItsTextAndImages() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        let image = try Self.image(width: 64)
        hub.with { $0.turnFailure = .noModel }
        await model.sendToHubChat("And this?", images: [image])?.value
        let back = try XCTUnwrap(model.takeUnsentHubDraft())
        XCTAssertEqual(back.text, "And this?")
        XCTAssertEqual(back.images.map(\.data), [image.data])

        hub.with { state in
            state.turnFailure = nil
            state.turnsDropped = 1
        }
        model.sendToHubChat("Again", images: [image])
        try await until("the dropped send") { hub.with(\.dropped).count == 1 && model.openHubReply?.reading == nil }
        model.selection = nil
        hub.with { $0.turnFailure = .replyInProgress }
        await model.scene(.foreground).value
        try await until("the refusal") { model.hubReplies.isEmpty }
        model.selection = .hub(providerID: config.id, chatID: 12)
        XCTAssertEqual(model.openedHubChat?.unsent?.text, "Again")
        XCTAssertEqual(model.openedHubChat?.unsent?.images.map(\.data), [image.data])
    }

    /// A send that goes nowhere here, to a Mac out of reach, keeps its
    /// images with its text.
    func testASendToAMacOutOfReachGivesBackItsImages() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        await model.disconnectPipe(for: config.id, leaving: .closed)
        let image = try Self.image(width: 64)
        XCTAssertNil(model.sendToHubChat("", images: [image]))
        XCTAssertEqual(model.openedHubChat?.notice, "home is unreachable.")
        XCTAssertEqual(model.openedHubChat?.unsent?.images.map(\.data), [image.data])
        XCTAssertEqual(hub.with(\.uploads).count, 0)
    }

    /// A Mac whose gglib is from before images says so in one sentence,
    /// whether its upload route is missing or its turn refuses the key, and
    /// the draft comes back.
    func testAMacWithoutImagesSaysItsGglibNeedsUpdating() async throws {
        let line = "The gglib on home needs updating before it can take images."
        let image = try Self.image(width: 64)
        for (upload, turn) in [(HubTurnFailure.takesNoImages, nil), (nil, HubTurnFailure.takesNoImages)] {
            let hub = FakeChatsHub()
            hub.with { state in
                state.uploadFailure = upload
                state.turnFailure = turn
            }
            let (model, _) = try await HubChatContinueTests.opened(hub)
            await model.sendToHubChat("And this?", images: [image])?.value
            XCTAssertEqual(hub.with(\.uploads).count, 1)
            XCTAssertEqual(model.openedHubChat?.notice, line)
            XCTAssertEqual(model.openedHubChat?.unsent?.images.map(\.id), [image.id])
        }
    }

    /// A chat whose model this phone knows cannot read images refuses an
    /// image here, with gglib's sentence, as it is added and as it is sent;
    /// one that can, or that this phone does not know, is sent them.
    func testAChatWhoseModelCannotSeeRefusesImagesHere() async throws {
        let hub = FakeChatsHub()
        let (model, config) = try await HubChatContinueTests.opened(hub)
        let open = try XCTUnwrap(model.openedHubChat)
        XCTAssertTrue(model.canSeeHubChat(open), "a model this phone has not read was refused")
        model.modelsByProvider[config.id] = [ModelInfo(id: "qwen3-8b")]
        XCTAssertFalse(model.canSeeHubChat(open))
        XCTAssertFalse(model.admitsImagesToHubChat())
        XCTAssertEqual(model.lastError, AppModel.cannotSee)
        let image = try Self.image(width: 64)
        XCTAssertNil(model.sendToHubChat("And this?", images: [image]))
        XCTAssertEqual(model.openedHubChat?.notice, AppModel.cannotSee)
        XCTAssertEqual(model.openedHubChat?.unsent?.images.map(\.id), [image.id])
        XCTAssertEqual(hub.with(\.uploads).count, 0)

        model.modelsByProvider[config.id] = [ModelInfo(id: "qwen3-8b", capabilities: ["vision"])]
        XCTAssertTrue(model.admitsImagesToHubChat())
        await model.sendToHubChat("And this?", images: [image])?.value
        XCTAssertEqual(hub.with(\.uploads).count, 1)
    }
}
