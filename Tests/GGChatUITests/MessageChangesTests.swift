import GGChatCore
import XCTest

@testable import GGChatUI

/// What a turn's menu does on this device's conversation (ADR 0010): Edit
/// opens the editor on the turn, Regenerate answers again on a branch, and
/// Branch from here copies and sends nothing. The editor saves only a
/// change.
final class MessageChangesTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:49993/v1")!

    @MainActor
    func testEachMenuItemMakesItsOwnChange() async throws {
        let registry = LoopbackProviderRegistry()
        let recorder = RecordingProvider(
            wrapping: MockProvider(scripts: [.init(text: "Day 1: temples"), .init(text: "Day 1: markets")]))
        registry.register(recorder, at: baseURL)
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try model.addProvider(
            ProviderConfig(name: "mock", kind: .openAICompatible(baseURL: baseURL), defaultModel: "mock-27b"),
            credentials: [:])
        model.newConversation()
        try await XCTUnwrap(model.send("Plan a trip to Kyoto")).value
        let original = try XCTUnwrap(model.selectedConversation)
        var edited: [Message] = []
        let changes = model.messageChanges(in: original.id) { edited.append($0) }

        changes.edit(original.messages[1])
        XCTAssertEqual(edited, [original.messages[1]])
        XCTAssertEqual(model.conversations.count, 1, "Edit changed something before the editor saved")

        changes.branch(original.messages[0].id)
        XCTAssertEqual(model.selectedConversation?.messages.map(\.content), ["Plan a trip to Kyoto"])
        XCTAssertEqual(recorder.requests.count, 1, "Branch from here sent something")

        changes.regenerate(original.messages[1].id)
        try await AppModelRunTests.until("the regenerated reply") {
            model.selectedConversation?.messages.count == 2 && !model.isStreaming
        }
        XCTAssertEqual(model.conversations.count, 3)
        XCTAssertEqual(recorder.requests.count, 2, "Regenerate answered nothing")
        XCTAssertEqual(model.selectedConversation?.branchOf, original.id)
    }

    @MainActor
    func testTheEditorSavesOnlyAChange() {
        let reply = Message(role: .assistant, content: "Day 1: temples\n", createdAt: .distantPast)
        XCTAssertTrue(MessageEditor.canSave("Day 1: gardens", for: reply))
        XCTAssertFalse(MessageEditor.canSave(" Day 1: temples ", for: reply), "the space around it is no change")
        XCTAssertFalse(MessageEditor.canSave("  \n", for: reply), "a blank reply")
        let image = ImageRef(id: "ab", mime: "image/png", width: 1, height: 1)
        let picture = Message(role: .user, content: "What is this?", createdAt: .distantPast, images: [image])
        XCTAssertTrue(MessageEditor.canSave("", for: picture), "a question of images alone")
    }
}
