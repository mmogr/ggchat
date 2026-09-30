/// Why the hub's chats could not be read.
public enum HubChatsFailure: Error, Sendable, Equatable {
    /// The hub reads its chats only to a device it paired, through its
    /// tunnel: `403 device_not_named`. This device reached it some other way,
    /// by its address say, so asking again the same way gets the same answer.
    case notShared
    /// The hub has no such chat, or no chats route at all: an older gglib.
    case notFound
    /// Any other 4xx, or a body that cannot be read.
    case refused(ProviderError)
    /// The hub could not be reached, answered 5xx, or something else answered
    /// in its place with a page that is not JSON. Asking again later may work.
    case dropped(ProviderError?)
}

/// A provider whose hub lets this device look at the hub's own chats, live.
/// gglib's `chats` routes. Nothing read through here is stored (ADR 0007).
public protocol HubChatsProvider: Provider {
    /// The hub's chats, the most recently changed first.
    func listChats() async throws(HubChatsFailure) -> HubChatList
    /// One chat and every row of it.
    func openChat(id: Int64) async throws(HubChatsFailure) -> HubChatOpen
}

/// The codes the hub's chats routes answer with.
public enum HubChatsCode {
    public static let deviceNotNamed = "device_not_named"
}
