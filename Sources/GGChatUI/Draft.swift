import Foundation

/// What the local composer holds before it is sent: text, images, or both.
/// It is emptied only when the model takes it, so a refused draft keeps its
/// text and its images.
struct Draft {
    var text = ""
    private(set) var images: [DraftImage] = []

    /// Whether there is anything to send: text that is not only spaces, or
    /// an image.
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    /// Adds an image after the others; the same image twice is one.
    mutating func add(_ image: DraftImage) {
        if !images.contains(where: { $0.id == image.id }) { images.append(image) }
    }

    mutating func remove(_ image: DraftImage) {
        images.removeAll { $0.id == image.id }
    }

    /// Hands the draft to `model` as the open conversation's next turn, and
    /// empties it once taken. A refused draft stays as it was.
    mutating func send(through model: AppModel) {
        guard model.send(text, images: images) else { return }
        self = Draft()
    }
}
