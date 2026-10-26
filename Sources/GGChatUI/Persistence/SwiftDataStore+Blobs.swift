import Foundation
import GGChatCore

// A conversation's encoded columns: what a row keeps as JSON rather than in
// a column of its own, read leniently and compared as values, so a write
// marks a row only when what it holds has changed. Its images are in
// `+Images`, which also owns their rows.
extension SwiftDataStore {
    /// A failure this build cannot read costs the failure and not the
    /// conversation, so it is `try?`: the transcript is what matters.
    static func failure(from data: Data?) -> Failure? {
        data.flatMap { try? JSONDecoder().decode(Failure.self, from: $0) }
    }

    /// Whether a message's failure is not the one its row holds. Compared as
    /// values, so the same failure written in other bytes is the same. Bytes
    /// this build cannot read differ from no failure, so they are cleared as
    /// before.
    static func failure(_ failure: Failure?, differsFrom data: Data?) -> Bool {
        guard let failure else { return data != nil }
        return Self.failure(from: data) != failure
    }

    /// A reading this build cannot read reads as none, as a failure does. It
    /// is compared with the conversation's as a value, so the row is written
    /// only when the reading has changed.
    static func reading(from data: Data?) -> ContextReading? {
        data.flatMap { try? JSONDecoder().decode(ContextReading.self, from: $0) }
    }

    /// The tools a reply called. A list this build cannot read reads as
    /// none, as a failure does, and none is written as nil, so a turn with
    /// none writes the row it always did.
    static func exchanges(from data: Data?) -> [ToolExchange] {
        data.flatMap { try? JSONDecoder().decode([ToolExchange].self, from: $0) } ?? []
    }

    static func data(of exchanges: [ToolExchange]) throws -> Data? {
        exchanges.isEmpty ? nil : try JSONEncoder().encode(exchanges)
    }

    /// Which servers the conversation uses. A choice this build cannot read
    /// reads as a new conversation's, as a failure reads as none, and that
    /// choice is written as nil, so a conversation that never picked writes
    /// no column. Compared as values, so it is written only when it changed.
    static func toolChoice(from data: Data?) -> ToolChoice {
        data.flatMap { try? JSONDecoder().decode(ToolChoice.self, from: $0) } ?? ToolChoice()
    }

    static func data(of choice: ToolChoice) throws -> Data? {
        choice.isDefault ? nil : try JSONEncoder().encode(choice)
    }
}
