import Foundation

/// What the conversation list's search field finds: a conversation kept
/// here by its title or anything said in it, a Mac's chat by its title, the
/// only thing of one this phone holds without reading it (ADR 0007). Case
/// and accents are ignored, and words may come in any order.
public struct ChatSearch: Equatable, Sendable {
    /// The words searched for, each of which must be found.
    let words: [String]

    /// A search for `query`; one of nothing but spaces finds everything.
    public init(_ query: String) {
        words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether the field holds anything to search for.
    public var isEmpty: Bool {
        words.isEmpty
    }

    /// Whether `conversation`'s title, or one of its messages, holds every
    /// word.
    public func finds(_ conversation: Conversation) -> Bool {
        finds(in: [conversation.displayTitle] + conversation.messages.map(\.content))
    }

    /// Whether a Mac's chat titled `title` holds every word.
    public func finds(title: String) -> Bool {
        finds(in: [title])
    }

    /// Whether every word is in one of `texts`, not necessarily the same one.
    private func finds(in texts: [String]) -> Bool {
        words.allSatisfy { word in
            texts.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
