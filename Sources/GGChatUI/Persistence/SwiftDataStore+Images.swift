import Foundation
import GGChatCore
import SwiftData

// An image's bytes are an `ImageRecord`, kept once under their id; a turn's
// row names its images in `imagesData`. A row no turn names is deleted when
// the last turn naming it goes, from a save or with its conversation.
extension SwiftDataStore {
    /// The same bytes saved twice are one row: the id is their hash.
    public func save(image: ImageRef, data: Data) throws {
        guard try fetchImage(image.id) == nil else { return }
        context.insert(
            ImageRecord(imageID: image.id, mime: image.mime, width: image.width, height: image.height, data: data))
        try context.save()
    }

    public func loadImage(id: String) throws -> Data? {
        try fetchImage(id)?.data
    }

    /// Deletes each of `ids` that no turn in the store names, and saves.
    public func deleteImages(noTurnNames ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        let named = try context.fetch(FetchDescriptor<MessageRecord>()).reduce(into: Set<String>()) { named, row in
            named.formUnion(Self.images(from: row.imagesData).map(\.id))
        }
        var deleted = false
        for id in ids.subtracting(named) {
            if let record = try fetchImage(id) {
                context.delete(record)
                deleted = true
            }
        }
        if deleted { try context.save() }
    }

    /// A list this build cannot read reads as none: the turn's text is what
    /// matters, as for a failure.
    static func images(from data: Data?) -> [ImageRef] {
        data.flatMap { try? JSONDecoder().decode([ImageRef].self, from: $0) } ?? []
    }

    /// Nil for none, so a turn with no images writes the row it always did.
    static func data(of images: [ImageRef]) throws -> Data? {
        images.isEmpty ? nil : try JSONEncoder().encode(images)
    }

    private func fetchImage(_ id: String) throws -> ImageRecord? {
        var descriptor = FetchDescriptor<ImageRecord>(predicate: #Predicate { $0.imageID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
