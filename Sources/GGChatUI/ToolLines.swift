/// The lines a reply being written shows for the tools it calls, one for
/// each call, in order. A line for a call the model is still writing
/// (`ChatEvent.tool`'s `writing`) stands only until the next tool line,
/// which takes its place: a later count for the same call, or the call
/// itself once it is written. gglib sends a call's counts before the call,
/// but a count of the next call can take a count's place before its own
/// call comes, so only the lines of calls written are sure to stand. Shown,
/// never kept: a finished reply has its rows instead.
struct ToolLines: Equatable {
    private(set) var lines: [String] = []
    /// Whether the last line is of a call still being written.
    private var lastIsWriting = false

    mutating func take(_ line: String, writing: Bool) {
        if lastIsWriting, !lines.isEmpty {
            lines[lines.count - 1] = line
        } else {
            lines.append(line)
        }
        lastIsWriting = writing
    }

    /// The reply has ended: a call still being written never will be, so
    /// its line goes.
    mutating func end() {
        if lastIsWriting { lines.removeLast() }
        lastIsWriting = false
    }
}
