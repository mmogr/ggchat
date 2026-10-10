import Foundation
import GGChatCore
import Observation

/// The reply being streamed right now. Only the last row observes it, so a
/// token touches one view and the transcript above it never re-lays out.
@Observable
public final class LiveReply {
    public let conversationID: UUID
    /// Set when Continue, or reading on from a run, streams into an existing
    /// message.
    public let continuingMessageID: UUID?
    public var content = ""
    public var reasoning = ""
    /// The latest word on how much of the prompt has been read. It lives here
    /// only: `finish` never reads it, so it is never stored.
    public var progress: PromptProgress?
    public var error: ProviderError?
    /// How far a picture being drawn has got, the latest look at it, and
    /// what the reply waits for: shown while it is so, and never kept
    /// (`ToolWork`).
    var work = ToolWork()
    /// A line for each tool the reply called, while it is read here.
    public internal(set) var tools: [String] = []
    /// The images the reply's tools made, in order, by reference. Their
    /// bytes are in this device's store by the time one is named here, and
    /// `finish` names them on the reply's message.
    public internal(set) var made: [ImageRef] = []
    /// How the run writes its events, as its `PUT` was answered or, for a
    /// reply read on, as its message kept it.
    var frames = RunFrames.openai
    /// What the last finished model call counted and why it ended, and the
    /// model the reply was asked of. `finish` makes the conversation's
    /// reading of them, and only for a reply that finished.
    var usage: Usage?
    var finishReason: String?
    var model: String?
    /// The pipe provider this reply is waiting for, until it connects; nil
    /// while it streams. See `AppModel+Waiting`.
    public internal(set) var waitingFor: UUID?
    /// The run the hub is writing this reply in, when it is one; see
    /// `AppModel+Runs`.
    public internal(set) var runID: String?
    /// The last of the run's events this reply holds, stored text included.
    var cursor: UInt32 = 0
    /// Whether the hub has answered the run's `PUT`. Until it has, the run may
    /// not exist, and the next reach sends the `PUT` again under the same id.
    var started = false
    /// Whether putting this reply down walks away from its run rather than
    /// stopping it: set on the way to the background, never by Stop.
    var detaching = false
    /// Whether the person stopped this reply, which is then never unread.
    var stoppedHere = false
    /// The content's markdown, kept between tokens; see `blocks`.
    @ObservationIgnored private var markdown = LiveMarkdown()

    /// The content as markdown blocks. A token parses only what follows the
    /// blocks it cannot change, not the whole reply again (`LiveMarkdown`).
    var blocks: [MarkdownBlock] {
        markdown.update(to: content)
        return markdown.blocks
    }

    init(conversationID: UUID, continuingMessageID: UUID?) {
        self.conversationID = conversationID
        self.continuingMessageID = continuingMessageID
    }

    /// Whether the reply shows the spinner: nothing of it has arrived, and no
    /// picture is being drawn or waited for in its place.
    var awaitsFirstToken: Bool {
        content.isEmpty && reasoning.isEmpty && work.isEmpty && made.isEmpty
    }

    /// "Reading 8,200 of 11,000 tokens", in `locale`'s digits, while the
    /// prompt is read: nil before the first progress frame, and once any text
    /// or reasoning has arrived.
    public func readingLine(in locale: Locale) -> String? {
        guard content.isEmpty, reasoning.isEmpty, let progress else { return nil }
        let processed = progress.processed.formatted(.number.locale(locale))
        let total = progress.total.formatted(.number.locale(locale))
        return "Reading \(processed) of \(total) tokens"
    }
}
