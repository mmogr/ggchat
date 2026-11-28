import SwiftUI

/// The rows a reply being written shows, in the order things happened, in
/// either kind of chat (`LiveRows`), each drawn alike.
struct LiveRowsView: View {
    let rows: [LiveRow]

    var body: some View {
        ForEach(rows) { row in
            LiveRowView(row: row)
        }
    }
}

/// One row of a reply being written: a mark that says its state, one line
/// of text and the detail after it, such as how long a tool took. It is one
/// line high in every state, since each mark is a symbol in the row's font
/// in a column of one width and the text never wraps, so a row that changes
/// does not move the rows around it. The state is never the colour alone:
/// each has its own mark, a failed row says "failed", and VoiceOver hears
/// the state in words, with how long it took.
struct LiveRowView: View {
    @ScaledMetric(relativeTo: .caption) private var markWidth: CGFloat = 14
    let row: LiveRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: Self.mark(for: row.state))
                .imageScale(.small)
                .foregroundStyle(row.state == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: markWidth)
            Text(row.text)
                .truncationMode(.tail)
            if let detail = row.detail {
                Text(detail)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
        .accessibilityValue(row.spokenTime ?? "")
        .accessibilityIdentifier(Self.identifier(for: row.kind))
    }

    /// The mark for each state, each its own shape: a call that runs, one
    /// done, and one that failed, which is #220's warning mark.
    static func mark(for state: LiveRow.State) -> String {
        switch state {
        case .running: "circle.dotted"
        case .done: "checkmark.circle"
        case .failed: ToolCallRow.failedSymbol
        }
    }

    /// What a walk finds a row by, by its kind.
    static func identifier(for kind: LiveRow.Kind) -> String {
        switch kind {
        case .tool: "live-tool-row"
        }
    }
}
