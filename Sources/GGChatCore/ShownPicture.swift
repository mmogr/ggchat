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
    /// image, on the first `user` message after that reply. A fix or a redo
    /// kept here is appended to its reply's images, so it is that last
    /// image. Nil when no reply drew one, or no `user` message follows it
    /// yet. Whether the model reads images is the caller's to ask.
    ///
    /// Nil too when that reply also holds an answered call of any other
    /// tool: a reply's images are every tool's, and which call made which
    /// is not kept, so its last image may be another tool's. An older drawn
    /// picture is not shown in its place, as one in that reply may be newer.
    public var shownPicture: ShownPicture? {
        guard
            let drawn = lastIndex(where: { message in
                message.role == .assistant && !message.images.isEmpty
                    && message.exchanges.contains { $0.name == HubToolCall.drawingTool && $0.result != nil }
            }),
            !self[drawn].exchanges.contains(where: { $0.name != HubToolCall.drawingTool && $0.result != nil }),
            let image = self[drawn].images.last,
            let at = self[(drawn + 1)...].firstIndex(where: { $0.role == .user })
        else { return nil }
        return ShownPicture(at: at, image: image)
    }
}
