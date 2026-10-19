@testable import GGChatUI

/// The single-reply view of the model the tests written before replies were
/// per conversation still read. Each of those starts at most one reply, so
/// "the reply in flight" names it; a test that starts two reads
/// `liveReplies` instead.
@MainActor
extension AppModel {
    /// The one reply in flight: nil when none is, and when more than one is.
    var liveReply: LiveReply? {
        liveReplies.count == 1 ? liveReplies.values.first : nil
    }

    /// Whether any conversation has a reply in flight.
    var isStreaming: Bool {
        !liveReplies.isEmpty
    }

    /// Stops the one reply in flight, if there is exactly one.
    func stop() {
        if let id = liveReply?.conversationID { stop(id) }
    }
}
