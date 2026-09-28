import Foundation
import GGChatCore
import XCTest

@testable import GGChatUI

/// The reset behind `-ggchat-reset YES`, handed to `open(at:resetRequested:log:)`
/// here. `open(log:)` reads the flag and names the real Application Support,
/// so no test calls it.
final class StoreResetTests: XCTestCase {
    private let scratch = StoreScratch()

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    #if DEBUG
        /// An open that does not ask for the reset keeps the store at both
        /// places. One that asks clears both before the move: nothing is moved
        /// in behind it, and it has nothing to report.
        @MainActor
        func testTheResetClearsTheStoreFromBothPlaces() throws {
            let location = scratch.location
            do {
                let store = SwiftDataStore(container: SwiftDataStore.open(at: location, log: NoopLogSink()).container)
                try store.save(conversation: StoreScratch.conversations(1, providerID: UUID())[0])
            }
            do {
                let older = SwiftDataStore(
                    container: try scratch.container(at: scratch.support.appending(path: "ggchat.store")))
                try older.save(conversation: StoreScratch.conversations(1, providerID: UUID())[0])
            }
            do {
                let kept = SwiftDataStore.open(at: location, log: NoopLogSink())
                XCTAssertEqual(kept.notice, StoreNotice(keptInMemory: false, olderStoreLeftBehind: true))
                XCTAssertEqual(try SwiftDataStore(container: kept.container).loadConversations().count, 1)
            }

            let opened = SwiftDataStore.open(at: location, resetRequested: true, log: NoopLogSink())

            XCTAssertNil(opened.notice)
            XCTAssertEqual(try SwiftDataStore(container: opened.container).loadConversations(), [])
            XCTAssertEqual(scratch.names(in: scratch.support).filter { $0.hasPrefix("ggchat.store") }, [])
        }
    #endif
}
