import Foundation
import Markdown

/// The transcript's shape: a flat list of blocks. Prose is an
/// `AttributedString` with inline styling; code is kept raw for the inset
/// panel and its copy button.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case code(language: String?, text: String)
    case list(ordered: Bool, items: [AttributedString])
    case quote([MarkdownBlock])
    case thematicBreak
    case table(MarkdownTable)
}

/// A GFM table: a header row, the rows under it, and how each column is
/// aligned. Every row has one cell per column, and a cell keeps its inline
/// styling as a paragraph does.
public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    /// One per column; nil where the delimiter row gave none.
    public let alignments: [Alignment?]
    public let header: [AttributedString]
    public let rows: [[AttributedString]]

    public init(alignments: [Alignment?], header: [AttributedString], rows: [[AttributedString]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

public enum MarkdownBlocks {
    /// Parses CommonMark. An unterminated fence, as seen mid-stream, is a
    /// code block to the end of the text, so streaming code never flashes
    /// as prose.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        blocks(of: Document(parsing: text).children)
    }

    /// The blocks for a document's top-level children.
    static func blocks(of children: some Sequence<any Markup>) -> [MarkdownBlock] {
        children.compactMap(block(for:))
    }

    private static func block(for markup: any Markup) -> MarkdownBlock? {
        switch markup {
        case let paragraph as Paragraph:
            return .paragraph(inline(paragraph))
        case let heading as Heading:
            return .heading(level: heading.level, inline(heading))
        case let code as CodeBlock:
            let language = code.language?.trimmingCharacters(in: .whitespaces)
            var text = code.code
            if text.hasSuffix("\n") { text.removeLast() }
            return .code(language: language.flatMap { $0.isEmpty ? nil : $0 }, text: text)
        case let list as UnorderedList:
            return .list(ordered: false, items: list.children.map(listItem(for:)))
        case let list as OrderedList:
            return .list(ordered: true, items: list.children.map(listItem(for:)))
        case let quote as BlockQuote:
            return .quote(quote.children.compactMap(block(for:)))
        case is ThematicBreak:
            return .thematicBreak
        case let html as HTMLBlock:
            return .code(language: "html", text: html.rawHTML)
        case let table as Table:
            return .table(self.table(table))
        default:
            return .paragraph(AttributedString(markup.format()))
        }
    }

    private static func table(_ table: Table) -> MarkdownTable {
        let alignments = table.columnAlignments.map { alignment -> MarkdownTable.Alignment? in
            switch alignment {
            case .left: .leading
            case .center: .center
            case .right: .trailing
            case nil: nil
            }
        }
        // The parser pads a short row with empty cells and cuts a long one
        // to the header's width, so every row arrives one cell per column.
        func cells(_ row: any Markup) -> [AttributedString] {
            row.children.compactMap { $0 as? Table.Cell }.map(cell(_:))
        }
        return MarkdownTable(
            alignments: alignments, header: cells(table.head), rows: table.body.children.map(cells(_:)))
    }

    /// The parser reads a cell holding only `^` as a mark that the cell above
    /// runs on into this row, and empties it. GitHub draws no such thing, so
    /// the mark is put back and drawn as written.
    private static func cell(_ cell: Table.Cell) -> AttributedString {
        cell.rowspan == 0 ? AttributedString("^") : inline(cell)
    }

    private static func listItem(for markup: any Markup) -> AttributedString {
        let pieces = markup.children.map { child -> AttributedString in
            if let paragraph = child as? Paragraph { return inline(paragraph) }
            return AttributedString(child.format().trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var joined = AttributedString()
        for (index, piece) in pieces.enumerated() {
            if index > 0 { joined += AttributedString("\n") }
            joined += piece
        }
        return joined
    }

    /// Inline styling via Foundation, which understands emphasis, strong,
    /// code spans and links.
    private static func inline(_ container: some Markup) -> AttributedString {
        // `format()` renders a node in the context of its ancestors, so a
        // paragraph inside a block quote comes back with its "> " marker and
        // one inside a list item comes back indented. Detaching drops that
        // context, leaving the inline markdown alone. A table cell is never
        // formatted itself, which the formatter refuses; only its children.
        let source: String = container.detachedFromParent.children.map { $0.format() }.joined()
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
