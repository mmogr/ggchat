/// Which of its paired Mac's MCP servers a conversation uses: a setting of
/// the conversation, as its Thinking choice is, kept by the servers' ids on
/// that Mac so a rename keeps a pick, and never pruned, since the Mac's
/// answer that it offers none may be a read that failed.
///
/// The master switch is stored apart from the picks. Turned off, a
/// conversation names no server and keeps what it picked, so turning it on
/// again restores them in one press. A new conversation is on with nothing
/// picked, so it names no server until one is picked.
public struct ToolChoice: Codable, Sendable, Equatable, Hashable {
    /// Whether the conversation's tools are switched off.
    public var off = false
    /// The servers picked, by their ids on the Mac.
    public var picked: Set<Int64> = []
    /// The servers this conversation has shown the person, by their ids on
    /// the Mac, whether they were picked or not.
    public var seen: Set<Int64> = []

    public init(off: Bool = false, picked: Set<Int64> = [], seen: Set<Int64> = []) {
        self.off = off
        self.picked = picked
        self.seen = seen
    }

    /// The servers a run names, sorted: none while off; the picks the Mac
    /// still offers when its offer is known; and every pick as kept while
    /// it is not, for the Mac to narrow to those it opens.
    public func servers(offered: [OfferedServer]?) -> [Int64] {
        guard !off else { return [] }
        guard let offered else { return picked.sorted() }
        return picked.intersection(offered.map(\.id)).sorted()
    }

    /// The choice with its master switch on or off, its picks kept.
    public func turned(on: Bool) -> ToolChoice {
        var choice = self
        choice.off = !on
        return choice
    }

    /// The choice with `server` picked or not.
    public func picking(_ server: Int64, _ isPicked: Bool) -> ToolChoice {
        var choice = self
        if isPicked { choice.picked.insert(server) } else { choice.picked.remove(server) }
        return choice
    }

    /// The choice having shown `servers` too.
    public func seeing(_ servers: some Sequence<Int64>) -> ToolChoice {
        var choice = self
        choice.seen.formUnion(servers)
        return choice
    }

    /// Whether this is a new conversation's choice: on, nothing picked,
    /// nothing seen.
    public var isDefault: Bool {
        self == ToolChoice()
    }

    enum CodingKeys: String, CodingKey {
        case off, picked, seen
    }

    /// Every key, always, and the sets as sorted lists: a key left out
    /// would fail the whole decode and reset the choice, and sorted lists
    /// give one choice one spelling.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(off, forKey: .off)
        try container.encode(picked.sorted(), forKey: .picked)
        try container.encode(seen.sorted(), forKey: .seen)
    }
}
