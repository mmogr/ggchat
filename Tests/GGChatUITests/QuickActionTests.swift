import GGChatCore
import XCTest

@testable import GGChatUI

/// What the app's icon offers, and how the conversation each starts begins.
@MainActor
final class QuickActionTests: XCTestCase {
    private func addressed(_ name: String = "mock", model: String = "mock-27b") -> ProviderConfig {
        ProviderConfig(
            name: name, kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:1/v1")!),
            defaultModel: model)
    }

    private func bare(_ providers: [ProviderConfig]) -> AppModel {
        let model = AppModel(store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink())
        model.providers = providers
        return model
    }

    /// Nothing is offered with no provider; a server added by address
    /// offers a new chat, and the camera only where there is one; Draw is
    /// offered only with a paired Mac that can draw or has not been asked,
    /// and never for one that said it cannot.
    func testTheIconOffersOnlyWhatCanBeStarted() async throws {
        XCTAssertEqual(bare([]).quickActions(hasCamera: true), [])
        XCTAssertEqual(bare([addressed()]).quickActions(hasCamera: false), [.newChat])
        XCTAssertEqual(bare([addressed()]).quickActions(hasCamera: true), [.newChat, .camera])
        let (paired, _) = try await DrawingRunTests.makeModel(behind: FakeRunHub(frames: []))
        XCTAssertEqual(paired.quickActions(hasCamera: true), [.newChat, .camera, .draw])
        let (unasked, _) = try await DrawingRunTests.makeModel(behind: FakeRunHub(frames: []), drawing: nil)
        XCTAssertEqual(unasked.quickActions(hasCamera: false), [.newChat, .draw])
        let cannot = Drawing(available: false, reason: "no image model")
        let (refused, _) = try await DrawingRunTests.makeModel(behind: FakeRunHub(frames: []), drawing: cannot)
        XCTAssertEqual(refused.quickActions(hasCamera: false), [.newChat], "Draw offered for a Mac that cannot draw")
    }

    /// A new chat with none open is with the first provider and leaves its
    /// composer no note; the camera's leaves one its own composer reads
    /// once, and no other conversation's reads at all.
    func testAChatStartedOnTheCameraTellsItsOwnComposerOnce() throws {
        let model = bare([addressed("first"), addressed("second")])
        model.perform(.newChat)
        XCTAssertEqual(model.selectedConversation?.providerID, model.providers[0].id)
        XCTAssertNil(model.composerStart)

        model.perform(.camera)
        let started = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(model.conversations.count, 2)
        XCTAssertEqual(started.providerID, model.providers[0].id)
        XCTAssertNil(model.takeComposerStart(for: model.conversations[1].id))
        XCTAssertEqual(model.takeComposerStart(for: started.id), .camera)
        XCTAssertNil(model.takeComposerStart(for: started.id))
    }

    /// Draw starts with the paired Mac, though another provider is first,
    /// and tells its composer to press Draw; with no paired Mac it starts
    /// nothing.
    func testDrawStartsWithThePairedMacAndNothingWithoutOne() async throws {
        let (model, mac) = try await DrawingRunTests.makeModel(behind: FakeRunHub(frames: []))
        model.providers.insert(addressed(), at: 0)
        let before = model.conversations.count
        model.perform(.draw)
        let started = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(model.conversations.count, before + 1)
        XCTAssertEqual(started.providerID, mac.id)
        XCTAssertEqual(model.takeComposerStart(for: started.id), .draw)

        let alone = bare([addressed()])
        alone.perform(.draw)
        XCTAssertTrue(alone.conversations.isEmpty)
        XCTAssertNil(alone.composerStart)
    }

    /// A new chat, from the list or the icon, is with the open
    /// conversation's provider, not the first one.
    func testANewChatIsWithTheOpenConversationsProvider() {
        let model = bare([addressed("first"), addressed("second")])
        model.newConversation(with: model.providers[1])
        XCTAssertEqual(model.newConversation().providerID, model.providers[1].id)
        model.perform(.camera)
        XCTAssertEqual(model.selectedConversation?.providerID, model.providers[1].id)
    }

    /// One open on a provider since removed starts the new chat with the
    /// first provider.
    func testANewChatIsWithTheFirstProviderWhenTheOpenOnesIsGone() {
        let model = bare([addressed("first"), addressed("second")])
        model.newConversation(with: model.providers[1])
        model.providers.remove(at: 1)
        XCTAssertEqual(model.newConversation().providerID, model.providers[0].id)
    }

    /// With a Mac's chat open, a new chat is with that Mac.
    func testANewChatIsWithTheMacWhoseChatIsOpen() {
        let model = bare([addressed("first"), addressed("second")])
        model.openedHubChat = OpenHubChat(providerID: model.providers[1].id, chatID: 7, title: "", state: .reading)
        XCTAssertEqual(model.newConversation().providerID, model.providers[1].id)
    }

    /// A conversation moved to another provider takes that provider's
    /// default model, and drops the Thinking choice and image model made
    /// for the one left; no provider's default changes.
    func testAConversationMovedToAnotherProviderTakesItsDefaultModel() throws {
        let model = bare([addressed("first"), addressed("second", model: "other-9b")])
        var conversation = model.newConversation()
        conversation.model = "mock-4b"
        conversation.thinkingOff = true
        conversation.imageModelID = 3
        model.update(conversation)
        model.select(provider: model.providers[1].id, for: conversation.id)
        let moved = try XCTUnwrap(model.selectedConversation)
        XCTAssertEqual(moved.providerID, model.providers[1].id)
        XCTAssertEqual(moved.model, "other-9b")
        XCTAssertFalse(moved.thinkingOff)
        XCTAssertNil(moved.imageModelID)
        XCTAssertEqual(model.providers.map(\.defaultModel), ["mock-27b", "other-9b"])
    }

    /// A conversation whose reply a hub is still writing stays where it was
    /// asked: the reply is read from that provider.
    func testAConversationAHubIsStillWritingStaysOnItsProvider() {
        let model = bare([addressed("first"), addressed("second")])
        var conversation = model.newConversation()
        conversation.messages = [Message(role: .assistant, content: "", createdAt: .distantPast, runID: "r1")]
        model.update(conversation)
        XCTAssertFalse(model.canChangeProvider(of: conversation))
        model.select(provider: model.providers[1].id, for: conversation.id)
        XCTAssertEqual(model.selectedConversation?.providerID, model.providers[0].id)
    }

    /// A quick action closes a picture left open whole, so the chat it
    /// starts is the one seen.
    func testAQuickActionClosesAPictureLeftOpen() throws {
        let model = bare([addressed()])
        let picture = try PictureFixture.picture()
        model.enlarged = EnlargedPicture(image: picture.ref, fromHub: false, owner: nil)
        model.perform(.newChat)
        XCTAssertNil(model.enlarged)
    }
}
