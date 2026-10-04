import Foundation

/// What a composer holds before it is sent: text, images, or both. It is
/// emptied only when the model takes it, so a refused draft keeps its text
/// and its images. A hub chat's draft is held in memory and never stored,
/// its images' bytes included.
struct Draft: Equatable {
    var text = ""
    private(set) var images: [DraftImage] = []

    init(text: String = "", images: [DraftImage] = []) {
        self.text = text
        for image in images { add(image) }
    }

    /// The same text and the same images in the same order. An image's id is
    /// the hash of its bytes, so the same id is the same bytes.
    static func == (lhs: Draft, rhs: Draft) -> Bool {
        lhs.text == rhs.text && lhs.images.map(\.id) == rhs.images.map(\.id)
    }

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
