import GGChatCore

/// One row of what a reply being written shows, in the order things
/// happened: what kind of row it is, one line of text, its state, and a
/// detail drawn after the text. Every kind is drawn alike (`LiveRowView`),
/// so a row of another kind can join the list with no change to these.
/// Shown, never kept.
struct LiveRow: Equatable, Identifiable {
    enum Kind: Equatable {
        /// A tool the reply calls, or one the model is still writing.
        case tool
    }

    enum State: Equatable {
        case running, done, failed
    }

    /// Its place in the list, which it keeps whatever it comes to say.
    let id: Int
    let kind: Kind
    var text: String
    var state: State
    /// What is drawn after the text: how long the call took once it is
    /// done, in gglib's words as they came, or that it failed. None while
    /// it runs, or when gglib did not say.
    var detail: String?
    /// The call the row is of, once that call has come: its end is read by
    /// it.
    var callID: String?

    /// The detail of a row whose tool said it failed.
    static let failedWord = "failed"

    /// What VoiceOver hears, as gglib's window says it: "Read File:
    /// Cargo.lock done.", "… failed.", or "… running." while it runs.
    var spoken: String {
        switch state {
        case .running: "\(text) running."
        case .done: "\(text) done."
        case .failed: "\(text) failed."
        }
    }

    /// What VoiceOver hears after the words: how long a call that is done
    /// took, when gglib said.
    var spokenTime: String? {
        state == .done ? detail : nil
    }
}

/// The rows a reply being written shows for the tools it calls, one for
/// each call, in order. A row for a call the model is still writing
/// (`ChatEvent.tool`'s `writing`) stands only until the next tool line,
/// which takes its place: a later count for the same call, or the call
/// itself once it is written. gglib sends a call's counts before the call,
/// but a count of the next call can take a count's place before its own
/// call comes, so only the rows of calls written are sure to stand.
///
/// A call's row runs until its call ends, and is then done, with how long
/// it took when gglib says, or failed when the tool said so. It is changed
/// in place, by the call's id, which the call's own event brings right
/// after its line; a row is never taken out and put back. Shown, never
/// kept: a finished reply has its rows instead (`ToolCallRows`).
struct LiveRows: Equatable {
    private(set) var rows: [LiveRow] = []
    /// Whether the last row is of a call still being written.
    private var lastIsWriting = false
    /// Whether the last event made a row for a call's own line, which the
    /// call that follows it names.
    private var lastAwaitsCall = false

    /// The rows' text, in order.
    var lines: [String] { rows.map(\.text) }

    /// Takes one event of the reply, every one of them, so that a call only
    /// names the row made by the line just before it.
    mutating func take(_ event: ChatEvent) {
        let awaitsCall = lastAwaitsCall
        lastAwaitsCall = false
        switch event {
        case .tool(let line, let writing):
            take(line, writing: writing)
            lastAwaitsCall = !writing
        case .toolCalled(let call):
            if awaitsCall { rows[rows.count - 1].callID = call.callID }
        case .toolEnded(let callID):
            settle(callID) { row in if row.state == .running { row.state = .done } }
        case .toolAnswered(let callID, _, let failed, let duration):
            settle(callID) { row in
                row.state = failed == true ? .failed : .done
                row.detail = failed == true ? LiveRow.failedWord : duration
            }
        default: break
        }
    }

    /// The reply has ended: a call still being written never will be, so
    /// its row goes.
    mutating func end() {
        if lastIsWriting { rows.removeLast() }
        lastIsWriting = false
        lastAwaitsCall = false
    }

    private mutating func take(_ line: String, writing: Bool) {
        if lastIsWriting, !rows.isEmpty {
            rows[rows.count - 1].text = line
        } else {
            rows.append(LiveRow(id: rows.count, kind: .tool, text: line, state: .running))
        }
        lastIsWriting = writing
    }

    /// Changes the row of the call `callID` names, if there is one.
    private mutating func settle(_ callID: String, _ change: (inout LiveRow) -> Void) {
        guard let index = rows.lastIndex(where: { $0.callID == callID }) else { return }
        change(&rows[index])
    }
}
