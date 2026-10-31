/// The drawn picture a request shows a model that reads images, and the
/// message it goes on: gglib's rule for a client that keeps its own chats
/// (gglib's `docs/clients.md`, Images). On the wire that message is sent as
/// ``line``, the picture, then its own parts.
public struct ShownPicture: Sendable, Equatable {
    /// The index, in the request's messages, of the `user` message that
    /// carries the picture.
    public var at: Int
    public var image: ImageRef

    public init(at: Int, image: ImageRef) {
        self.at = at
        self.image = image
    }

    /// The text part that goes ahead of the picture, gglib's own words for
    /// it (`DRAWN_PICTURE_LINE` there): whose the image is, and that the
    /// tool's "you cannot" does not hold for this one.
    public static let line =
        "(Added automatically, not written by the person: the image below is the most recent picture the "
        + "drawing tool made in this conversation, the same one the person sees. You can see it now, although "
        + "the tool's answer said you could not. The person's own message follows.)"
}

extension [Message] {
    /// The drawn picture these messages show: the last image of the latest
    /// reply that holds an answered call of gglib's drawing tool and an
    /// image no other tool made, on the first `user` message after that
    /// reply. A reply's images are every tool's, and each answered call
    /// keeps the ids of the ones it made (``ToolExchange/images``), so an
    /// image another tool of the reply made, a search's or a chart's, is
    /// passed over. A fix or a redo kept here is appended to its reply's
    /// images and is no call's, so it is that last image. Nil when no reply
    /// drew one, or no `user` message follows it yet. Whether the model
    /// reads images is the caller's to ask. A reply whose every image
    /// another tool made drew none, as one whose draw failed and made no
    /// image, and the picture before it is shown.
    public var shownPicture: ShownPicture? {
        for drawn in indices.reversed() {
            let message = self[drawn]
            guard message.role == .assistant, !message.images.isEmpty,
                message.exchanges.contains(where: { $0.name == HubToolCall.drawingTool && $0.result != nil })
            else { continue }
            let theirs = Set(message.exchanges.filter { $0.name != HubToolCall.drawingTool }.flatMap(\.images))
            guard let image = message.images.last(where: { !theirs.contains($0.id) }) else { continue }
            guard let at = self[(drawn + 1)...].firstIndex(where: { $0.role == .user }) else { return nil }
            return ShownPicture(at: at, image: image)
        }
        return nil
    }
}
