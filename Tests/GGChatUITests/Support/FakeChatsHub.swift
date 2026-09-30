import GGChatCore
import Synchronization

/// A gglib hub's chats, in process: a list, and the chats it opens. Every
/// list and open is recorded.
final class FakeChatsHub: HubChatsProvider {
    struct State {
        var list: Result<HubChatList, HubChatsFailure>
        var chats: [Int64: HubChatOpen] = [:]
        var lists = 0
        var opens: [Int64] = []
        /// Holds every open until it is set false again.
        var holdsOpens = false
        /// Answers every open with this, when set.
        var openFailure: HubChatsFailure?
    }

    let state: Mutex<State>

    init(_ chats: [HubChatSummary] = FakeChatsHub.summaries) {
        state = Mutex(State(list: .success(HubChatList(chats: chats)), chats: [12: Self.opened]))
    }

    /// The two chats gglib's recorded list holds.
    static let summaries = [
        HubChatSummary(
            id: 12, title: "Why the build broke", modelID: 3, model: "qwen3-8b", updatedAt: "2026-09-30 09:13:07",
            liveRun: "chat-5b1e"),
        HubChatSummary(id: 9, title: "New Chat", updatedAt: "2026-09-29 18:02:41"),
    ]

    /// Chat 12 as gglib's recorded open holds it, with a system row, a tool
    /// row and a reply that only called a tool around its two turns.
    static let opened = HubChatOpen(
        conversation: HubConversation(
            id: 12, title: "Why the build broke", modelID: 3, createdAt: "2026-09-30 09:12:30",
            updatedAt: "2026-09-30 09:13:07"),
        messages: [
            HubMessage(id: 39, conversationID: 12, role: "system", content: "Be brief.", createdAt: "a"),
            HubMessage(id: 40, conversationID: 12, role: "user", content: "Why did the build break?", createdAt: "b"),
            HubMessage(id: 41, conversationID: 12, role: "assistant", content: "", createdAt: "c"),
            HubMessage(id: 42, conversationID: 12, role: "tool", content: "exit 1", createdAt: "d"),
            HubMessage(id: 43, conversationID: 12, role: "assistant", content: "A dependency moved.", createdAt: "e"),
        ])

    func with<T>(_ body: (inout State) -> T) -> T {
        state.withLock { body(&$0) }
    }

    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { $0.finish() }
    }

    func listChats() async throws(HubChatsFailure) -> HubChatList {
        try with { state in
            state.lists += 1
            return state.list
        }.get()
    }

    func openChat(id: Int64) async throws(HubChatsFailure) -> HubChatOpen {
        with { $0.opens.append(id) }
        while with({ $0.holdsOpens }) { await Task.yield() }
        let (chat, failure) = with { ($0.chats[id], $0.openFailure) }
        if let failure { throw failure }
        guard let chat else { throw .notFound }
        return chat
    }
}
