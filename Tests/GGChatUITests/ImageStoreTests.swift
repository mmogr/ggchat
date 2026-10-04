import Foundation
import GGChatCore
import SwiftData
import XCTest

@testable import GGChatUI

/// The rows as the build before images declared them, for opening a store
/// across the change in both directions.
enum BeforeImages {
    @Model
    final class ConversationRecord {
        @Attribute(.unique) var uuid: UUID
        var title: String
        var providerID: UUID?
        var model: String?
        var systemPrompt: String?
        var createdAt: Date
        var updatedAt: Date
        var hasUnreadReply: Bool?
        @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
        var messages: [MessageRecord] = []

        init(id: UUID, title: String, createdAt: Date) {
            self.uuid = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }

    @Model
    final class MessageRecord {
        @Attribute(.unique) var uuid: UUID
        var role: String
        var content: String
        var reasoning: String?
        var isPartial: Bool
        var failureData: Data?
        var runID: String?
        var runCursor: Int?
        var createdAt: Date
        var order: Int
        var conversation: ConversationRecord?

        init(id: UUID, role: String, content: String, createdAt: Date, order: Int) {
            self.uuid = id
            self.role = role
            self.content = content
            self.isPartial = false
            self.createdAt = createdAt
            self.order = order
        }
    }
}

/// A turn's images are kept with it: the turn names them, and their bytes
/// are kept once each, in a file beside the store, until the last turn that
/// names one goes. A reset leaves none of those files behind.
@MainActor
final class ImageStoreTests: XCTestCase {
    private let scratch = StoreScratch()
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try FileManager.default.createDirectory(at: scratch.support, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        scratch.remove()
        try super.tearDownWithError()
    }

    private static func image(_ byte: UInt8, count: Int = 16) -> (ImageRef, Data) {
        let data = Data(repeating: byte, count: count)
        return (ImageRef(id: ImageRef.id(of: data), mime: ImageRef.png, width: 8, height: 4), data)
    }

    private func conversation(_ turns: [[ImageRef]]) -> Conversation {
        Conversation(
            providerID: UUID(), model: "m",
            messages: turns.enumerated().map { index, images in
                Message(role: .user, content: "turn \(index)", createdAt: stamp, images: images)
            },
            createdAt: stamp, updatedAt: stamp)
    }

    /// A turn names its images in order, and both they and their bytes are
    /// there after the store is opened again. A turn with none writes no
    /// list, as its row did before images.
    func testATurnsImagesAndTheirBytesOutliveAReopening() throws {
        let url = scratch.support.appending(path: "images.store")
        let (first, firstBytes) = Self.image(1)
        let (second, secondBytes) = Self.image(2)
        let kept = conversation([[second, first], []])
        do {
            let store = SwiftDataStore(container: try scratch.container(at: url))
            try store.save(image: first, data: firstBytes)
            try store.save(image: second, data: secondBytes)
            try store.save(image: first, data: firstBytes)
            try store.save(conversation: kept)
        }
        let store = SwiftDataStore(container: try scratch.container(at: url))
        let loaded = try XCTUnwrap(try store.loadConversations().first)
        XCTAssertEqual(loaded.messages.map(\.images), [[second, first], []])
        XCTAssertEqual(loaded, kept)
        XCTAssertEqual(try store.loadImage(id: first.id), firstBytes)
        XCTAssertEqual(try store.loadImage(id: second.id), secondBytes)
        XCTAssertEqual(try store.container.mainContext.fetchCount(FetchDescriptor<ImageRecord>()), 2)
        XCTAssertNil(try store.loadImage(id: Self.image(3).0.id))
        let rows = try store.container.mainContext.fetch(
            FetchDescriptor<MessageRecord>(sortBy: [SortDescriptor(\.order)]))
        XCTAssertEqual(rows.map { $0.imagesData == nil }, [false, true], "a turn with no images wrote a list")
    }

    /// An image goes with the last turn that names it: deleting a
    /// conversation keeps one another conversation names, and a save that
    /// takes a turn away, or an image off a turn, deletes what nothing names.
    func testAnImageGoesWithTheLastTurnThatNamesIt() throws {
        let store = SwiftDataStore(container: SwiftDataStore.inMemoryContainer())
        let (shared, sharedBytes) = Self.image(1)
        let (own, ownBytes) = Self.image(2)
        let (later, laterBytes) = Self.image(3)
        for (image, data) in [(shared, sharedBytes), (own, ownBytes), (later, laterBytes)] {
            try store.save(image: image, data: data)
        }
        let gone = conversation([[own, shared]])
        var stays = conversation([[shared], [later]])
        try store.save(conversation: gone)
        try store.save(conversation: stays)
        XCTAssertEqual(try store.loadImage(id: own.id), ownBytes)

        try store.deleteConversation(id: gone.id)
        XCTAssertNil(try store.loadImage(id: own.id), "an image no turn names was kept")
        XCTAssertEqual(try store.loadImage(id: shared.id), sharedBytes, "an image another turn names was deleted")

        stays.messages.removeFirst()
        try store.save(conversation: stays)
        XCTAssertNil(try store.loadImage(id: shared.id), "the image of a turn taken away was kept")
        XCTAssertEqual(try store.loadImage(id: later.id), laterBytes)

        stays.messages[0].images = []
        try store.save(conversation: stays)
        XCTAssertNil(try store.loadImage(id: later.id), "an image taken off its turn was kept")
        XCTAssertEqual(try store.container.mainContext.fetchCount(FetchDescriptor<ImageRecord>()), 0)
    }

    /// A store the build before images wrote opens in this one, its turns
    /// with none, and one this build wrote, images kept, opens under the
    /// earlier schema with its text.
    func testAStoreOpensAcrossTheImagesChangeInBothDirections() throws {
        let earlierSchema = Schema([
            ProviderRecord.self, BeforeImages.ConversationRecord.self, BeforeImages.MessageRecord.self,
        ])
        func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
            let configuration = ModelConfiguration("ggchat", schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let older = scratch.support.appending(path: "older.store")
        do {
            let written = try container(earlierSchema, at: older)
            let record = BeforeImages.ConversationRecord(id: UUID(), title: "before", createdAt: stamp)
            written.mainContext.insert(record)
            let row = BeforeImages.MessageRecord(id: UUID(), role: "user", content: "hello", createdAt: stamp, order: 0)
            row.conversation = record
            written.mainContext.insert(row)
            try written.mainContext.save()
        }
        let opened = SwiftDataStore(container: try container(SwiftDataStore.schema, at: older))
        let read = try XCTUnwrap(try opened.loadConversations().first)
        XCTAssertEqual(read.messages.map(\.content), ["hello"])
        XCTAssertEqual(read.messages.map(\.images), [[]])

        let newer = scratch.support.appending(path: "newer.store")
        let (image, bytes) = Self.image(1, count: 200_000)
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            try store.save(image: image, data: bytes)
            try store.save(conversation: conversation([[image]]))
        }
        do {
            let store = SwiftDataStore(container: try container(SwiftDataStore.schema, at: newer))
            XCTAssertEqual(try store.loadConversations().first?.messages.map(\.images), [[image]])
            XCTAssertEqual(try store.loadImage(id: image.id), bytes)
        }
        let earlier = try container(earlierSchema, at: newer)
        let rows = try earlier.mainContext.fetch(FetchDescriptor<BeforeImages.MessageRecord>())
        XCTAssertEqual(rows.map(\.content), ["turn 0"])
    }

    #if DEBUG
        /// An image's bytes are a file in the hidden folder beside the store,
        /// not a row in it, and the reset removes that folder with the store:
        /// after it, no image file is left anywhere under Application Support.
        func testTheResetLeavesNoImageFileBehind() throws {
            let location = scratch.location
            let (image, bytes) = Self.image(7, count: 1_000_000)
            do {
                let store = SwiftDataStore(container: SwiftDataStore.open(at: location, log: NoopLogSink()).container)
                try store.save(image: image, data: bytes)
                try store.save(conversation: conversation([[image]]))
            }
            let folder = StoreDirectory.externalStorage(of: location.storeURL)
            XCTAssertEqual(folder.lastPathComponent, ".ggchat_SUPPORT")
            XCTAssertEqual(
                folder.deletingLastPathComponent().standardizedFileURL, location.directory.standardizedFileURL)
            let files = scratch.names(in: folder.appending(path: "_EXTERNAL_DATA"))
            XCTAssertEqual(files.count, 1, "the image's bytes are not a file beside the store")
            let file = try Data(contentsOf: folder.appending(path: "_EXTERNAL_DATA").appending(path: files[0]))
            XCTAssertEqual(file, bytes)

            let opened = SwiftDataStore.open(at: location, resetRequested: true, log: NoopLogSink())

            XCTAssertFalse(scratch.exists(folder), "the folder of image files outlived the reset")
            let left =
                FileManager.default.enumerator(atPath: scratch.support.path(percentEncoded: false))?
                .compactMap { $0 as? String }.filter { $0.contains("_EXTERNAL_DATA/") } ?? []
            XCTAssertEqual(left, [])
            XCTAssertNil(try SwiftDataStore(container: opened.container).loadImage(id: image.id))
        }
    #endif
}
