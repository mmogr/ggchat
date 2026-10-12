import Foundation
import GGChatCore
import Synchronization

/// A Mac that draws a picture again, in process: every request is recorded,
/// and each render says `script`, the first it holds before waiting until
/// it is let go.
final class FakePictures: Sendable {
    struct State {
        /// Every picture asked to be drawn again, in order.
        var asked: [PictureRedraw] = []
        /// What each render says, in order.
        var script: [RedrawEvent] = [.drawn(FakePictures.drawn)]
        /// How many of a render's events are passed on before it waits.
        var holdAt: Int?
        /// How many renders ended with their reader gone.
        var left = 0
    }

    /// The bytes a render answers with, as it stands.
    static let drawn = Data("A FOX DRAWN AGAIN".utf8)

    let state = Mutex(State())

    func with<T>(_ body: (inout State) -> T) -> T {
        state.withLock { body(&$0) }
    }

    /// Lets every held render go on.
    func release() {
        with { $0.holdAt = nil }
    }

    func redraw(_ redraw: PictureRedraw) -> AsyncStream<RedrawEvent> {
        let script = with { state in
            state.asked.append(redraw)
            return state.script
        }
        return AsyncStream { continuation in
            let task = Task {
                for (at, event) in script.enumerated() {
                    while self.with({ $0.holdAt == at }), !Task.isCancelled { await Task.yield() }
                    if Task.isCancelled {
                        self.with { $0.left += 1 }
                        return
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension FakeRunHub: PictureProvider {
    func redraw(_ redraw: PictureRedraw) -> AsyncStream<RedrawEvent> {
        pictures.redraw(redraw)
    }
}

extension FakeChatsHub: PictureProvider {
    /// The Mac that draws for its chats: `runs.pictures`.
    var pictures: FakePictures { runs.pictures }

    func redraw(_ redraw: PictureRedraw) -> AsyncStream<RedrawEvent> {
        pictures.redraw(redraw)
    }

    /// Links `kept.image` to the latest tool row of the chat that carries
    /// `kept.from`, after the images that row has, and answers the row's
    /// images, as gglib does. An image it does not hold, a chat it does not
    /// have and a picture no tool row carries are refused.
    func keepPicture(chatID: Int64, _ kept: KeptPicture) async throws(ProviderError) -> [ImageRef] {
        let answer: Result<[ImageRef], ProviderError> = with { state in
            state.kept.append((chatID, kept))
            if let failure = state.keepFailure { return .failure(failure) }
            guard let chat = state.chats[chatID],
                let at = chat.messages.lastIndex(where: { row in
                    row.role == "tool" && row.images?.contains { $0.id == kept.from } == true
                })
            else { return .failure(.server(status: 404, code: "conversation_not_found", message: "no such chat")) }
            guard state.images[kept.image] != nil else {
                return .failure(.server(status: 400, code: "attachment_not_found", message: "no such image"))
            }
            let row = chat.messages[at]
            var images = row.images ?? []
            if !images.contains(where: { $0.id == kept.image }) {
                images.append(ImageRef(id: kept.image, mime: ImageRef.png, width: 64, height: 32))
            }
            var rows = chat.messages
            rows[at] = HubMessage(
                id: row.id, conversationID: row.conversationID, role: row.role, content: row.content,
                createdAt: row.createdAt, metadata: row.metadata, images: images)
            state.chats[chatID] = HubChatOpen(conversation: chat.conversation, messages: rows)
            return .success(images)
        }
        return try answer.get()
    }
}
