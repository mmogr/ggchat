import Foundation
import GGChatCore
import Observation

/// A reply a paired Mac is writing to one of its chats, carried on from this
/// phone. It lives in memory only: its text is read from the run's events and
/// is the Mac's to keep, and once the run ends the row the Mac saved takes
/// its place (ADR 0007). Apart from `LiveReply`, which is a reply to a
/// conversation kept here.
@Observable
public final class HubLiveReply {
    public let providerID: UUID
    public let chatID: Int64
    /// The run the Mac writes the reply in, minted here.
    public let runID: String
    /// What this phone sent, drawn under the chat until the Mac's rows hold
    /// it.
    public let question: String?
    /// The images sent with it, bytes and all, held here in memory until the
    /// run ends: a turn put again sends them again, and nothing of them is
    /// written to this phone (ADR 0007).
    let images: [DraftImage]
    public internal(set) var content = ""
    public internal(set) var reasoning = ""
    /// A line for each tool the reply called.
    public internal(set) var tools: [String] = []
    /// What the run's last finished model call counted and why it ended, once
    /// one has: the chat's reading while this reply is on screen, in memory
    /// like the rest of it.
    var usage: Usage?
    var finishReason: String?
    /// Names the reply's pauses between read-ons; see `readOnAfterAPause`.
    let key = UUID()
    /// The last of the run's events this reply holds.
    var cursor: UInt32 = 0
    /// The ids the Mac holds the images under, once each was answered by
    /// `POST attachments`. A turn put again sends them only when it does not.
    @ObservationIgnored var uploaded: [String]?
    /// Whether the Mac has answered the turn's `PUT`. Until it has, the run
    /// may not exist, and the next read sends the `PUT` again under its id.
    var started = false
    /// Whether putting the reading down walks away from the run rather than
    /// stopping it: set on leaving the chat and on the way to the background,
    /// never by Stop.
    var detaching = false
    /// Whether the run has ended. The reply stays on screen until the rows
    /// the Mac saved are read in its place.
    var ended = false
    /// The reading under way, if one is.
    @ObservationIgnored var reading: Task<Void, Never>?
    /// The content's markdown, kept between deltas; see `blocks`.
    @ObservationIgnored private var markdown = LiveMarkdown()

    /// The content as markdown blocks. A delta parses only what follows the
    /// blocks it cannot change, not the whole reply again (`LiveMarkdown`).
    var blocks: [MarkdownBlock] {
        markdown.update(to: content)
        return markdown.blocks
    }

    init(providerID: UUID, chatID: Int64, runID: String, question: String?, images: [DraftImage] = []) {
        self.providerID = providerID
        self.chatID = chatID
        self.runID = runID
        self.question = question
        self.images = images
    }

    /// Adds one event of the run to the reply. Its text, its reasoning and
    /// its tool calls are drawn, and what a finished call counted is kept,
    /// the last one over any before it; the run's last report says how it
    /// ended.
    func apply(_ event: ChatEvent) {
        switch event {
        case .delta(let text): content += text
        case .reasoning(let text): reasoning += text
        case .tool(let line): tools.append(line)
        case .usage(let counted, let reason):
            usage = counted
            finishReason = reason
        case .progress, .error, .finished: break
        }
    }
}
