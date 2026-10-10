import GGChatCore
import XCTest

@testable import GGChatUI

/// A branch's lineage is kept (ADR 0010): the conversation it was branched
/// from, the first of its family, and the message each copy copies.
final class BranchStoreTests: XCTestCase {
    @MainActor
    func testABranchsLineageSurvivesTheRoundTrip() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Conversation(
            title: "Kyoto", messages: [Message(role: .user, content: "Plan a trip", createdAt: stamp)],
            createdAt: stamp, updatedAt: stamp)
        let branch = try original.applying(.branch(messageID: original.messages[0].id), busy: false, now: stamp)
            .conversation
        try store.save(conversation: original)
        try store.save(conversation: branch)

        let loaded = try store.loadConversations()

        let kept = try XCTUnwrap(loaded.first { $0.id == branch.id })
        XCTAssertEqual(kept, branch)
        XCTAssertEqual(kept.branchOf, original.id)
        XCTAssertEqual(kept.family, original.id)
        XCTAssertEqual(kept.messages.first?.originID, original.messages[0].id)
        XCTAssertNil(loaded.first { $0.id == original.id }?.family, "an original names a family")
    }
}
