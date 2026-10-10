import Foundation

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
    /// Asks the Mac to make a change to one of its chats, by its branching
    /// rules (ADR 0010): in place, or on a new branch the answer names.
    func changeChat(id: Int64, change: HubChatChange) async throws(HubChatsFailure) -> HubChatChanged
    /// Adds `turn` to one of the hub's chats, and the hub writes the reply as
    /// the agent run `runID`, an id this device minted as for its own runs. A
    /// repeated id answers with the run already there.
    func startTurn(runID: String, turn: HubTurn) async throws(HubTurnFailure) -> RunStart
    /// The reply's events numbered above `after`, then its end: its text, its
    /// reasoning and a line for each tool it calls.
    func turnEvents(runID: String, after: UInt32) -> AsyncStream<RunEvent>
    /// Stops the reply. Idempotent.
    func cancelTurn(runID: String) async throws(ProviderError) -> RunInfo
    /// Sends the hub an image a turn will name, as its bytes, and answers how
    /// the hub names it. The same bytes twice are one image there.
    func uploadImage(_ data: Data, mime: String) async throws(HubTurnFailure) -> ImageRef
    /// The bytes of an image one of the hub's chats names, for this device
    /// to hold in memory and nowhere else.
    func fetchImage(id: String) async throws(HubChatsFailure) -> Data
}

/// The codes the hub's chats routes answer with.
public enum HubChatsCode {
    public static let deviceNotNamed = "device_not_named"
    /// A turn with no model named, none running and no default.
    public static let noModel = "no_model"
    /// A turn on a chat the hub does not have.
    public static let conversationNotFound = "conversation_not_found"
}
