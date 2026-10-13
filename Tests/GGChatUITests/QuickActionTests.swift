import GGChatCore
import XCTest

@testable import GGChatUI

/// What the app's icon offers, and how the conversation each starts begins.
@MainActor
final class QuickActionTests: XCTestCase {
    private func addressed(_ name: String = "mock") -> ProviderConfig {
        ProviderConfig(
            name: name, kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:1/v1")!),
            defaultModel: "mock-27b")
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

    /// A new chat is with the first provider and leaves its composer no
    /// note; the camera's leaves one its own composer reads once, and no
    /// other conversation's reads at all.
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
