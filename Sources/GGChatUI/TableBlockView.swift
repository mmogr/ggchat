import GGChatCore
import SwiftUI

/// A markdown table drawn as one: the header row set apart, a cell's inline
/// styling kept as a paragraph's is, and the whole scrolled sideways when it
/// is wider than the transcript. A long cell wraps rather than running off
/// in a line of its own, and the cells beside it start at the top of the
/// row. VoiceOver reads it a row at a time, each cell after the name of its
/// column.
struct TableBlockView: View {
    let table: MarkdownTable
    /// Where a cell wraps. It grows with the text size, but never past most
    /// of the width on screen, so a cell can be read without scrolling.
    @ScaledMetric(relativeTo: .body) private var wrapWidth: CGFloat = 240
    @State private var visibleWidth: CGFloat = 0

    private var cellLimit: CGFloat {
        visibleWidth > 0 ? min(wrapWidth, max(visibleWidth * 0.8, 80)) : wrapWidth
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, text in
                        cell(text, column: column)
                            .fontWeight(.semibold)
                            .gridColumnAlignment(Self.horizontal(alignment(of: column)))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, text in
                            cell(text, column: column)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            visibleWidth = $0
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityChildren {
            ForEach(Array(Self.spokenRows(table).enumerated()), id: \.offset) { index, line in
                Text(line)
                    .accessibilityAddTraits(index == 0 ? .isHeader : [])
            }
        }
        .accessibilityLabel("Table")
    }

    private func alignment(of column: Int) -> MarkdownTable.Alignment? {
        table.alignments.indices.contains(column) ? table.alignments[column] : nil
    }

    private func cell(_ text: AttributedString, column: Int) -> some View {
        WrappingCell(limit: cellLimit) {
            Text(text)
                .multilineTextAlignment(Self.textAlignment(alignment(of: column)))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// What VoiceOver reads for each row, the header's first: the header's
    /// cells in order, then each row's cells after their column's name. An
    /// empty cell is left out, and so is the name of a column that has none.
    static func spokenRows(_ table: MarkdownTable) -> [String] {
        let names = table.header.map { String($0.characters) }
        let header = names.filter { !$0.isEmpty }.joined(separator: ", ")
        let rows = table.rows.map { row in
            zip(names, row).compactMap { name, cell -> String? in
                let value = String(cell.characters)
                guard !value.isEmpty else { return nil }
                return name.isEmpty ? value : "\(name): \(value)"
            }
            .joined(separator: ", ")
        }
        return [header] + rows
    }

    private static func horizontal(_ alignment: MarkdownTable.Alignment?) -> HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        case .leading, nil: .leading
        }
    }

    private static func textAlignment(_ alignment: MarkdownTable.Alignment?) -> TextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        case .leading, nil: .leading
        }
    }
}

/// A cell as wide as its text, up to `limit`, and wrapped past it. Inside a
/// sideways scroll view a text is offered all the width it wants, and would
/// otherwise take a long cell's whole text as one line.
private struct WrappingCell: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let cell = subviews.first else { return .zero }
        let width = min(cell.sizeThatFits(.unspecified).width, limit)
        return cell.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
