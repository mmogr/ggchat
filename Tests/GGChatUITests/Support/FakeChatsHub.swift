import Foundation
import GGChatCore
import Synchronization

/// A gglib hub's chats, in process: a list, and the chats it opens. Every
/// list and open is recorded.
final class FakeChatsHub: HubChatsProvider {
    struct State {
        var list: Result<HubChatList, HubChatsFailure>
        var chats: [Int64: HubChatOpen] = [:]
        var lists = 0
        /// Holds every list, once counted, until it is set false again.
        var holdsLists = false
        var opens: [Int64] = []
        /// Holds every open until it is set false again.
        var holdsOpens = false
        /// Answers every open with this, when set.
        var openFailure: HubChatsFailure?
        /// Every turn started, and what the next ones are answered with.
        var turns: [(runID: String, turn: HubTurn)] = []
        var turnFailure: HubTurnFailure?
        /// How many turns start and then lose their answer on the way back.
        var turnsLost = 0
        /// How many turns never reach the Mac: the answer is lost, and the
        /// run ids of those are kept here rather than in `turns`.
        var turnsDropped = 0
        var dropped: [String] = []
        /// How many turns wait until their `PUT` is cancelled, and are then
        /// dropped as above.
        var turnsHeldUntilCancelled = 0
        /// The kind of run a turn starts: a gglib that does not know turns
        /// starts a chat run.
        var turnKind = RunKind.agent
        /// How the run a turn starts stands when the answer comes back.
        var turnStatus = RunStatus.queued
        /// Holds every cancel until it is set false again, and counts them.
        var holdsCancels = false
        var cancelsAsked = 0
        /// The images the Mac holds, by id: each upload adds one, and a turn
        /// naming one it does not hold is refused with `imageGone`.
        var images: [String: Data] = [:]
        /// The bytes of every upload, in order, and what the next ones are
        /// answered with.
        var uploads: [Data] = []
        var uploadFailure: HubTurnFailure?
        /// How many uploads are answered and then not held, as if the Mac
        /// had let them go before the turn that names them.
        var forgetsUploads = 0
        /// The id of every image read, in order, and what the next reads are
        /// answered with.
        var fetches: [String] = []
        var fetchFailure: HubChatsFailure?
        /// Holds every read of an image, once counted, until it is set false.
        var holdsFetches = false
    }

    let state: Mutex<State>
    /// The runs the turns start, with every read and cancel they get: one
    /// reply, recorded as frames numbered from 1.
    let runs: FakeRunHub

    init(_ chats: [HubChatSummary] = FakeChatsHub.summaries, reply: [[ChatEvent]] = FakeChatsHub.reply) {
        state = Mutex(State(list: .success(HubChatList(chats: chats)), chats: [12: Self.opened]))
        runs = FakeRunHub(frames: reply)
    }

    /// The reply every turn's run writes: a tool call, reasoning, then text.
    static let reply: [[ChatEvent]] =
        [[.tool("Read File: Cargo.lock")]] + FakeRunHub.frames(ofText: "Pin the version.", reasoning: "It moved.")

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

    /// Chat 12 as the Mac saves it once a turn's reply is written.
    static func saved(_ question: String, _ answer: String) -> HubChatOpen {
        HubChatOpen(
            conversation: opened.conversation,
            messages: opened.messages + [
                HubMessage(id: 44, conversationID: 12, role: "user", content: question, createdAt: "f"),
                HubMessage(id: 45, conversationID: 12, role: "assistant", content: answer, createdAt: "g"),
            ])
    }

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
        with { $0.lists += 1 }
        while with({ $0.holdsLists }) { await Task.yield() }
        return try with(\.list).get()
    }

    func openChat(id: Int64) async throws(HubChatsFailure) -> HubChatOpen {
        with { $0.opens.append(id) }
        while with({ $0.holdsOpens }) { await Task.yield() }
        let (chat, failure) = with { ($0.chats[id], $0.openFailure) }
        if let failure { throw failure }
        guard let chat else { throw .notFound }
        return chat
    }

    func startTurn(runID: String, turn: HubTurn) async throws(HubTurnFailure) -> RunStart {
        if with({ $0.turnsHeldUntilCancelled > 0 }) {
            with { $0.turnsHeldUntilCancelled -= 1 }
            while !Task.isCancelled { await Task.yield() }
            with { $0.dropped.append(runID) }
            throw .lost(.transport("the turn was cut short"))
        }
        let isDropped = with { state in
            guard state.turnsDropped > 0 else { return false }
            state.turnsDropped -= 1
            state.dropped.append(runID)
            return true
        }
        if isDropped { throw .lost(.transport("the turn never arrived")) }
        let gone = with { state in
            guard turn.images.contains(where: { state.images[$0] == nil }) else { return false }
            state.turns.append((runID, turn))
            return true
        }
        if gone { throw .imageGone }
        let (failure, lost, info) = with { state in
            state.turns.append((runID, turn))
            state.turnsLost -= 1
            let info = RunInfo(
                id: runID, kind: state.turnKind, status: state.turnStatus, createdAtMs: 1_790_000_000_000, lastSeq: 0)
            return (state.turnFailure, state.turnsLost >= 0, info)
        }
        if let failure { throw failure }
        if lost { throw .lost(.transport("the answer was lost")) }
        return .started(info)
    }

    func turnEvents(runID: String, after: UInt32) -> AsyncStream<RunEvent> {
        runs.runEvents(id: runID, after: after)
    }

    func uploadImage(_ data: Data, mime: String) async throws(HubTurnFailure) -> ImageRef {
        let failure = with { state in
            state.uploads.append(data)
            return state.uploadFailure
        }
        if let failure { throw failure }
        let id = ImageRef.id(of: data)
        with { state in
            if state.forgetsUploads > 0 { state.forgetsUploads -= 1 } else { state.images[id] = data }
        }
        return ImageRef(id: id, mime: mime, width: 1, height: 1)
    }

    func fetchImage(id: String) async throws(HubChatsFailure) -> Data {
        let (data, failure) = with { state in
            state.fetches.append(id)
            return (state.images[id], state.fetchFailure)
        }
        while with({ $0.holdsFetches }) { await Task.yield() }
        if let failure { throw failure }
        guard let data else { throw .notFound }
        return data
    }

    func cancelTurn(runID: String) async throws(ProviderError) -> RunInfo {
        with { $0.cancelsAsked += 1 }
        while with({ $0.holdsCancels }) { await Task.yield() }
        return try await runs.cancelRun(id: runID)
    }
}
