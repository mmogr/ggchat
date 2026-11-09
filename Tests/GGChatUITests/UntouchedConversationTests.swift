import XCTest

@testable import GGChatCore
@testable import GGChatUI

/// The list keeps at most one untouched conversation, the one open: New
/// conversation on it is that one again, it goes when another is opened, and
/// a launch clears those an older build left behind. Anything a person chose
/// in it keeps it.
@MainActor
final class UntouchedConversationTests: XCTestCase {
    private func addressed(_ name: String = "mock") -> ProviderConfig {
        ProviderConfig(
            name: name, kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:1/v1")!),
            defaultModel: "mock-27b")
    }

    private func bare(_ providers: [ProviderConfig], store: any Store = InMemoryStore()) -> AppModel {
        let model = AppModel(store: store, secrets: InMemorySecrets(), log: NoopLogSink())
        model.providers = providers
        return model
    }

    func testNewConversationOnAnUntouchedOneIsThatOneAgain() {
        let model = bare([addressed()])
        let first = model.newConversation()
        let again = model.newConversation()
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(model.conversations.map(\.id), [first.id])
    }

    func testLeavingAnUntouchedConversationDeletesIt() throws {
        let store = InMemoryStore()
        let model = bare([addressed()], store: store)
        let kept = model.newConversation()
        model.renameConversation(kept.id, to: "Kept")
        let untouched = model.newConversation()
        model.selection = .local(kept.id)
        XCTAssertEqual(model.conversations.map(\.id), [kept.id])
        XCTAssertFalse(try store.loadConversations().contains { $0.id == untouched.id }, "the store kept it")
        XCTAssertEqual(model.selection, .local(kept.id), "the deletion took the selection with it")
    }

    func testANewConversationWithAnotherProviderLeavesOneUntouched() {
        let model = bare([addressed("first"), addressed("second")])
        let first = model.newConversation(with: model.providers[0])
        let second = model.newConversation(with: model.providers[1])
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(model.conversations.map(\.id), [second.id])
        XCTAssertEqual(model.selection, .local(second.id))
    }

    func testAnythingChosenKeepsIt() {
        let choices: [(String, (AppModel, UUID) -> Void)] = [
            ("a system prompt", { $0.setSystemPrompt("Answer in French.", for: $1) }),
            ("a name", { $0.renameConversation($1, to: "Named") }),
            ("another model", { $0.select(model: "mock-4b", for: $1) }),
            ("Thinking off", { $0.setThinking(off: true, for: $1) }),
            ("tools off", { $0.setTools(on: false, for: $1) }),
        ]
        for (what, choose) in choices {
            let model = bare([addressed()])
            let chosen = model.newConversation()
            choose(model, chosen.id)
            let next = model.newConversation()
            XCTAssertNotEqual(next.id, chosen.id, "New conversation reopened one with \(what)")
            XCTAssertTrue(model.conversations.contains { $0.id == chosen.id }, "one with \(what) was deleted")
        }
    }

    func testALaunchClearsTheUntouchedOnesAnOlderBuildLeft() throws {
        let store = InMemoryStore()
        let config = addressed()
        try store.save(provider: config)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        func saved(_ minutes: Double, title: String = "") throws -> Conversation {
            let conversation = Conversation(
                title: title, providerID: config.id, model: config.defaultModel,
                createdAt: stamp.addingTimeInterval(minutes * 60), updatedAt: stamp.addingTimeInterval(minutes * 60))
            try store.save(conversation: conversation)
            return conversation
        }
        let newest = try saved(3)
        let named = try saved(2, title: "Named")
        _ = try saved(1)
        _ = try saved(0)

        let model = bare([], store: store)
        model.load()
        XCTAssertEqual(model.conversations.map(\.id), [newest.id, named.id])
        XCTAssertEqual(model.selection, .local(newest.id), "the newest, untouched, is not reopened")
        XCTAssertEqual(Set(try store.loadConversations().map(\.id)), [newest.id, named.id])
    }
}
