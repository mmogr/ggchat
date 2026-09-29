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
    /// The pipe provider this reply is waiting for, until it connects; nil
    /// while it streams. See `AppModel+Waiting`.
    public internal(set) var waitingFor: UUID?
    /// The run the hub is writing this reply in, when it is one; see
    /// `AppModel+Runs`.
    public internal(set) var runID: String?
    /// The last of the run's events this reply holds, stored text included.
    var cursor: UInt32 = 0
    /// Whether putting this reply down walks away from its run rather than
    /// stopping it: set on the way to the background, never by Stop.
    var detaching = false

    init(conversationID: UUID, continuingMessageID: UUID?) {
        self.conversationID = conversationID
        self.continuingMessageID = continuingMessageID
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
