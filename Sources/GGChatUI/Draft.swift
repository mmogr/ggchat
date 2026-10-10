import Foundation

/// What a composer holds before it is sent: text, images, or both, and
/// whether Draw is pressed for it. It is emptied only when the model takes
/// it, so a refused draft keeps its text and its images. A hub chat's draft
/// is held in memory and never stored, its images' bytes included.
struct Draft: Equatable {
    var text = ""
    private(set) var images: [DraftImage] = []
    /// Whether Draw is pressed for this message: its reply may then have a
    /// picture made. It is the draft's and no setting of the chat, so it is
    /// off again in the empty draft a send leaves, and a draft given back
    /// has it as it was sent.
    var draws = false

    init(text: String = "", images: [DraftImage] = [], draws: Bool = false) {
        self.text = text
        self.draws = draws
        for image in images { add(image) }
    }

    /// The same text and the same images in the same order. An image's id is
    /// the hash of its bytes, so the same id is the same bytes. Draw is not
    /// compared: a composer with nothing in it but the switch is empty.
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

    /// Hands the draft to `model` as the next turn of the Mac's chat open,
    /// and empties it at once. A send that goes nowhere gives the draft
    /// back through the chat (`takeUnsentHubDraft`), Draw as it was.
    mutating func sendToHubChat(through model: AppModel) {
        let sent = self
        self = Draft()
        model.sendToHubChat(sent.text, images: sent.images, draws: sent.draws)
    }
}
